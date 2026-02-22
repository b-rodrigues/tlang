library(jsonlite)

# Function to send JSON message
send_msg <- function(con, msg) {
  body <- toJSON(msg, auto_unbox = TRUE)
  header <- sprintf("Content-Length: %d\r\n\r\n", nchar(body, type = "bytes"))
  cat(header, file = con, sep = "")
  cat(body, file = con, sep = "")
  flush(con)
}

# Function to receive JSON message
receive_msg <- function(con) {
  line <- readLines(con, n = 1)
  if (length(line) == 0 || !grepl("^Content-Length:", line)) return(NULL)

  len <- as.integer(sub("Content-Length: ", "", line))

  # Skip blank separator line
  while (nchar(readLines(con, n = 1)) > 0) {}

  # Read body
  body <- readChar(con, len)
  fromJSON(body)
}

# Start the LSP server and perform a minimal initialize/shutdown exchange
proc <- pipe("./_build/default/src/lsp_server.exe", "r+b")
on.exit(close(proc))

# Send initialize request
initialize_msg <- list(
  jsonrpc = "2.0",
  id      = 1,
  method  = "initialize",
  params  = list(
    processId = Sys.getpid(),
    rootUri   = NULL,
    capabilities = list()
  )
)
send_msg(proc, initialize_msg)

# Read initialize response
init_response <- receive_msg(proc)
print(init_response)

# Send shutdown request
shutdown_msg <- list(
  jsonrpc = "2.0",
  id      = 2,
  method  = "shutdown",
  params  = NULL
)
send_msg(proc, shutdown_msg)

# Read shutdown response
shutdown_response <- receive_msg(proc)
print(shutdown_response)

# Send exit notification to terminate the server
exit_msg <- list(
  jsonrpc = "2.0",
  method  = "exit",
  params  = NULL
)
send_msg(proc, exit_msg)
