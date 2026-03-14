local t_state = {
  chunks = {}
}

local function has_class(el, class_name)
  for _, class in ipairs(el.classes) do
    if class == class_name then
      return true
    end
  end
  return false
end

local function split_lines(text)
  local lines = {}
  if text == "" then
    return lines
  end

  text = text:gsub("\r\n", "\n")
  text = text:gsub("\r", "\n")

  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end

  return lines
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_bool(value, default)
  if value == nil then
    return default
  end

  local lowered = trim(tostring(value)):lower()
  if lowered == "true" then
    return true
  end
  if lowered == "false" then
    return false
  end

  return default
end

local function parse_chunk_options(text)
  local options = {}
  local body_lines = {}
  local parsing_options = true

  for _, line in ipairs(split_lines(text)) do
    local key, value = line:match("^%s*#|%s*([%w_-]+)%s*:%s*(.-)%s*$")
    if parsing_options and key ~= nil then
      options[key] = value
    else
      parsing_options = false
      table.insert(body_lines, line)
    end
  end

  return options, table.concat(body_lines, "\n")
end

local function write_file(path, content)
  local handle, open_err = io.open(path, "w")
  if handle == nil then
    error(open_err)
  end

  handle:write(content)
  handle:close()
end

local function render_error(message)
  return pandoc.CodeBlock(
    "T execution failed:\n" .. tostring(message),
    pandoc.Attr("", { "text", "t-error" })
  )
end

local function execute_t(chunk_source)
  local temp_path = os.tmpname()
  write_file(temp_path, chunk_source)

  local binary = os.getenv("TLANG_BIN") or "t"
  local ok, output = pcall(pandoc.pipe, binary, { "--mode", "strict", "--unsafe", "run", temp_path }, "")

  os.remove(temp_path)
  return ok, output
end

local function make_output_block(output)
  if output == nil or output == "" then
    return nil
  end

  return pandoc.CodeBlock(output, pandoc.Attr("", { "text", "t-output" }))
end

function CodeBlock(el)
  if not has_class(el, "t") then
    return nil
  end

  local options, body = parse_chunk_options(el.text)
  local include = normalize_bool(options.include, true)
  local should_eval = normalize_bool(options.eval, true)
  local show_code = normalize_bool(options.echo, true)
  local show_output = include and normalize_bool(options.output, true)
  local results = options.results and trim(options.results):lower() or nil

  if results == "hide" then
    show_output = false
  end

  if trim(body) == "" then
    return include and el or {}
  end

  local rendered_blocks = {}

  if include and show_code then
    table.insert(rendered_blocks, pandoc.CodeBlock(body, el.attr))
  end

  if not should_eval then
    return rendered_blocks
  end

  local session_chunks = {}
  for _, chunk in ipairs(t_state.chunks) do
    table.insert(session_chunks, chunk)
  end
  table.insert(session_chunks, body)

  local ok, output = execute_t(table.concat(session_chunks, "\n\n"))
  if not ok then
    if include then
      table.insert(rendered_blocks, render_error(output))
      return rendered_blocks
    end
    return {}
  end

  table.insert(t_state.chunks, body)

  if show_output then
    local output_block = make_output_block(output)
    if output_block ~= nil then
      table.insert(rendered_blocks, output_block)
    end
  end

  return rendered_blocks
end
