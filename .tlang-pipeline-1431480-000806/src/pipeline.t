p = pipeline {
  cached_node = shn(command = "echo -n 'artifact_roundtrip'", capture = "stdout")
}
