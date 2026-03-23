report_node = read_node("shell_report")
report_text = read_file(report_node.path)

print("Shell report artifact path:")
print(report_node.path)
print("")
print("Shell report contents:")
print(report_text)

ok = (contains(report_text, "Polyglot summary report") && contains(report_text, "raw_data artifact:") && contains(report_text, "R summary") && contains(report_text, "Python summary") && contains(report_text, "avg_mpg"))

if (ok) {
    print("Shell polyglot pipeline verified!")
} else {
    print("ERROR: shell report missing expected content")
    exit(1)
}
