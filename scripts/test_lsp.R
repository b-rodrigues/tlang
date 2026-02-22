library(jsonlite)

# Function to send JSON message
send_msg <- function(con, msg) {
  body <- toJSON(msg, auto_unbox = TRUE)
  header <- sprintf("Content-Length: %d\r\n\r\n", nchar(body))
  cat(header, file = con)
  cat(body, file = con)
  flush(con)
}

# Function to receive JSON message
receive_msg <- function(con) {
  line <- readLines(con, n = 1)
  if (length(line) == 0 || !grepl("^Content-Length:", line)) return(NULL)
  
  len <- as.integer(sub("Content-Length: ", "", line))
  
  # Skip headers
  while(readLines(con, n = 1) != "") {}
  
  # Read body
  body <- readChar(con, len)
  fromJSON(body)
}

# Start the server
proc <- pipe("./_build/default/src/lsp_server.exe", "w+b")
con <- proc

# Use a workaround for pipe since pipe() in R is usually one-way or tricky for bi-directional
# Let's use system2 with redirection for a simpler test if possible, 
# but bi-directional is better for LSP.

# Since R's pipe is not great for bi-directional, let's use a temporary file approach 
# or just trust the build was successful if it passed.

# Actually, I'll try to use a local python if possible.
# Wait, I'm on linux, python3 is almost always there.
