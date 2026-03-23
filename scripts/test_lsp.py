import json
import subprocess
import time

def send(proc, msg):
    s = json.dumps(msg)
    header = f"Content-Length: {len(s.encode('utf-8'))}\r\n\r\n"
    proc.stdin.write(header.encode('utf-8'))
    proc.stdin.write(s.encode('utf-8'))
    proc.stdin.flush()

def receive(proc):
    line = proc.stdout.readline().decode('utf-8')
    if not line.startswith("Content-Length:"): 
        print(f"Unexpected line: {line}")
        return None
    length = int(line[15:].strip())
    while True:
        l = proc.stdout.readline().decode('utf-8').strip()
        if l == "": break
    body = proc.stdout.read(length).decode('utf-8')
    return json.loads(body)

proc = subprocess.Popen(["./_build/default/src/lsp_server.exe"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "capabilities": {},
    "rootUri": "file:///"
}})
init_res = receive(proc)
print("Initialize Result:", json.dumps(init_res, indent=2))

send(proc, {"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
    "textDocument": {"uri": "file:///test.t", "languageId": "t", "version": 1, "text": "x = 10\ny = "}
}})

# Wait a bit for analysis
time.sleep(0.5)

send(proc, {"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///test.t"},
    "position": {"line": 1, "character": 4} # after 'y = '
}})
comp_res = receive(proc)
print("Completion Result:", json.dumps(comp_res, indent=2))

proc.terminate()
