import os
import re

def check_documentation(directory):
    undocumented = []
    # Regex to match Env.add "name"
    env_add_re = re.compile(r'Env\.add\s+"([^"]+)"')
    # Regex to match TDoc block with @name
    tdoc_re = re.compile(r'--#\s+@name\s+([^\s\n]+)')

    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.ml'):
                path = os.path.join(root, file)
                with open(path, 'r') as f:
                    content = f.read()
                
                # Find all documented names in this file
                documented_names = set(tdoc_re.findall(content))
                
                # Find all Env.add calls
                for match in env_add_re.finditer(content):
                    name = match.group(1)
                    if name not in documented_names:
                        # Check if it's documented but maybe the @name is different or missing
                        # We look for --# nearby (within 500 chars)
                        pos = match.start()
                        preceding = content[max(0, pos-1000):pos]
                        following = content[pos:min(len(content), pos+500)]
                        if '--#' not in preceding and '--#' not in following:
                            undocumented.append((path, name))

    return undocumented

if __name__ == "__main__":
    undocumented = check_documentation('src/packages')
    if not undocumented:
        print("All functions documented!")
    else:
        print(f"Found {len(undocumented)} potentially undocumented functions:")
        for path, name in undocumented:
            print(f"  {path}: {name}")
