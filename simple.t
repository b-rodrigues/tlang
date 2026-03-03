?<{echo "Hello from shell!"}>
name = ?<{whoami}>
print(paste("Hello, ", name))
?<{cd /tmp}>
print(paste("Current dir: ", ?<{pwd}>))
?<{cd ~}>
print(paste("Back home: ", ?<{pwd}>))
