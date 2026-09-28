# VHS Tape for T Language Demo
Output docs/demo.gif
Output demo.gif

Set FontSize 14
Set Width 900
Set Height 580
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar "Rings"
Set TypingSpeed 40ms

# Setup path invisibly
Hide
Type "export PATH=/tmp/tbin:$PATH; export PS1='$ '; clear"
Enter
Sleep 500ms
Show

# Run the live interactive demo
Type "t demo"
Enter
Sleep 3.5s

# Slide 1: The Pipeline as a First-Class Value
Enter
Sleep 4s

# Slide 2: Inspecting the Pipeline DAG
Enter
Sleep 4s

# Slide 3: Building into the Nix Store
Enter
Sleep 4s

# Slide 4: Inspecting Artifacts in Memory
Enter
Sleep 4s

# Slide 5: Growing the Pipeline & Content Caching
Enter
Sleep 4.5s

# Slide 6: First-Class Errors & Polyglot Soft-Failures
Enter
Sleep 5s

# Slide 7: Interactive REPL Handoff
Enter
Sleep 2.5s

# Try commands in live REPL
Type "read_node(p.filtered)"
Enter
Sleep 2.5s

Type "read_node(p.anomaly)"
Enter
Sleep 3s

Type ":quit"
Enter
Sleep 1.5s
