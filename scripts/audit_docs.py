#!/usr/bin/env python3
import os
import re
import json
import sys

def get_exported_functions(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Find functions registered with Env.add "name"
    # Env.add "mean" (make_builtin ...
    # Env.add "sum" (make_builtin ...
    matches = re.finditer(r'Env\.add\s+"([^"]+)"', content)
    return [m.group(1) for m in matches]

def has_tdoc(file_path, func_name):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Look for --# @name func_name
    pattern = rf'--#\s+@name\s+{re.escape(func_name)}(?:\s|$)'
    return re.search(pattern, content) is not None

def main():
    packages_dir = 'src/packages'
    undocumented = []
    
    for root, dirs, files in os.walk(packages_dir):
        for file in files:
            if file.endswith('.ml') and file != 'packages.ml':
                path = os.path.join(root, file)
                funcs = get_exported_functions(path)
                for func in funcs:
                    if not has_tdoc(path, func):
                        undocumented.append((path, func))
    
    if undocumented:
        print("Found undocumented public functions:")
        for path, func in undocumented:
            print(f"  {path}: {func}")
        sys.exit(1)
    else:
        print("All public functions are documented.")
        sys.exit(0)

if __name__ == "__main__":
    main()
