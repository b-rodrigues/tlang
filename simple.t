?<{echo "Hello from shell!"}>
name = ?<{whoami}>
print(str_join(["Hello, ", name]))
?<{cd /tmp}>
print(str_join(["Current dir: ", ?<{pwd}>]))
?<{cd ~}>
print(str_join(["Back home: ", ?<{pwd}>]))
