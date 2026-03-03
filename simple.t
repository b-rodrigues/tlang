?<{echo "Hello from shell!"}>
name = ?<{whoami}>
print(join(["Hello, ", name]))
?<{cd /tmp}>
print(join(["Current dir: ", ?<{pwd}>]))
?<{cd ~}>
print(join(["Back home: ", ?<{pwd}>]))
