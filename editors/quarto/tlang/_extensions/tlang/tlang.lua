local t_state = {session_source = ""}

local function has_class(el, class_name)
    for _, class in ipairs(el.classes) do
        -- Strip any surrounding {} and convert to lower for robustness
        local clean_class = class:gsub("^{", ""):gsub("}$", ""):lower()
        if clean_class == class_name:lower() then return true end
    end
    return false
end

local function split_lines(text)
    local lines = {}
    if text == "" then return lines end

    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")

    for line in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end

    return lines
end

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

local function normalize_bool(value, default)
    if value == nil then return default end

    local lowered = trim(tostring(value)):lower()
    if lowered == "true" then return true end
    if lowered == "false" then return false end

    return default
end

local function parse_chunk_options(text)
    local options = {}
    local body_lines = {}
    local parsing_options = true

    for _, line in ipairs(split_lines(text)) do
        -- Accept Quarto-style leading chunk options such as:
        --   #| echo: false
        --   #| results: hide
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
    if handle == nil then error(open_err) end

    handle:write(content)
    handle:close()
end

local function resolve_binary()
    local binary = os.getenv("TLANG_BIN")
    if binary == nil or trim(binary) == "" then return "t" end

    if binary:match("[\r\n]") ~= nil or binary:match("%z") ~= nil then
        error("TLANG_BIN must point to a single executable path.")
    end

    local normalized = binary
    if binary:match("^[A-Za-z]:[\\/]") ~= nil then
        normalized = binary:sub(3)
    elseif binary:match(":") ~= nil then
        error("TLANG_BIN may only use ':' in a Windows drive prefix.")
    end

    if not normalized:match("^[%w%._/%-\\]+$") then
        error("TLANG_BIN contains unsupported characters.")
    end

    if normalized:match("%.%.") ~= nil then
        error("TLANG_BIN may not contain parent-directory traversal segments.")
    end

    if binary:match("[/\\]") ~= nil then
        local handle = io.open(binary, "r")
        if handle == nil then
            error("TLANG_BIN does not point to a readable executable path.")
        end
        handle:close()
    end

    return binary
end

local function render_error(message)
    return pandoc.CodeBlock("T execution failed:\n" .. tostring(message),
                            pandoc.Attr("", {"text", "t-error"}))
end

-- Execute Quarto T chunks in strict mode while intentionally bypassing the
-- normal pipeline-only script guard so prose-first documents can render.
local function execute_t_unsafe(chunk_source)
    if pandoc.system == nil or pandoc.system.with_temporary_directory == nil then
        return false,
               "This Quarto filter requires pandoc.system.with_temporary_directory()."
    end

    local binary_ok, binary = pcall(resolve_binary)
    if not binary_ok then return false, tostring(binary) end
    local function run_temp_script(temp_path)
        write_file(temp_path, chunk_source)
        -- pandoc.pipe executes the binary directly with argv, not through a shell.
        return pcall(pandoc.pipe, binary,
                     {"--mode", "strict", "--unsafe", "run", temp_path}, "")
    end

    local wrapped_ok, ok, output = pcall(pandoc.system.with_temporary_directory,
                                         "tlang", function(temp_dir)
        return run_temp_script(temp_dir .. "/chunk.t")
    end)
    if not wrapped_ok then return false, tostring(ok) end

    if ok then return true, output end

    local message = tostring(output)
    if message:match("not found") or message:match("No such file") then
        return false, string.format(
                   "Could not run `%s`. Make sure the T CLI is installed or set TLANG_BIN to the correct binary.\n%s",
                   binary, message)
    end
    return false, message
end

local function make_output_block(output)
    if output == nil or output == "" then return nil end

    return pandoc.CodeBlock(output, pandoc.Attr("", {"text", "t-output"}))
end

-- ---------------------------------------------------------------------------
-- T syntax highlighting
--
-- Mirrors pandoc's R highlighting so T code is styled identically to R. Both a
-- raw HTML block (short-class spans, used by HTML/EPUB) and a raw LaTeX block
-- (\*Tok commands, used by PDF) are emitted; pandoc keeps only the one that
-- matches the output format.
-- ---------------------------------------------------------------------------

local T_KEYWORDS = {
    ["if"] = true, ["else"] = true, import = true, ["function"] = true,
    pipeline = true, intent = true, match = true, ["in"] = true,
}

local T_CONSTANTS = {
    NA = true, ["true"] = true, ["false"] = true,
}

-- Longest operators first so multi-character operators win over prefixes.
local T_OPERATORS = {
    "?|>", "!!!", ".<=", ".>=", ".==", ".!=",
    "|>", "::", "->", "=>", ":=", "==", "!=", "<=", ">=", "&&", "||", "!!",
    ".+", ".-", ".*", "./", ".%", ".<", ".>", ".&", ".|",
    "+", "-", "*", "/", "<", ">", "=", "~", "$", "%", "&", "|", "!", ".", ":",
}

local HTML_ESCAPES = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
}

local LATEX_ESCAPES = {
    ["\\"] = "\\textbackslash{}",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["_"] = "\\_",
    ["&"] = "\\&",
    ["#"] = "\\#",
    ["%"] = "\\%",
    ["^"] = "\\^{}",
    ["<"] = "\\textless{}",
    [">"] = "\\textgreater{}",
    ["-"] = "{-}",
    ["~"] = "\\textasciitilde{}",
}

local LATEX_TOK_CMD = {
    co = "CommentTok",
    st = "StringTok",
    dv = "DecValTok",
    fl = "FloatTok",
    cf = "ControlFlowTok",
    sc = "SpecialCharTok",
    fu = "FunctionTok",
    cn = "ConstantTok",
    ot = "OtherTok",
}

local function escape_map(s, map)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        table.insert(out, map[c] or c)
    end
    return table.concat(out)
end

local function match_operator(line, i)
    for _, op in ipairs(T_OPERATORS) do
        if line:sub(i, i + #op - 1) == op then
            return op
        end
    end
    return nil
end

local function tokenize_line(line)
    local tokens = {}
    local i, n = 1, #line

    while i <= n do
        local c = line:sub(i, i)

        if c == "-" and line:sub(i, i + 1) == "--" then
            table.insert(tokens, {cls = "co", text = line:sub(i, n)})
            i = n + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local cj = line:sub(j, j)
                if cj == "\\" then
                    j = j + 2
                elseif cj == c then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            table.insert(tokens, {cls = "st", text = line:sub(i, j - 1)})
            i = j
        elseif c:match("%d") then
            local j = i
            while j <= n and line:sub(j, j):match("%d") do j = j + 1 end
            if j <= n and line:sub(j, j) == "." and line:sub(j + 1, j + 1):match("%d") then
                j = j + 1
                while j <= n and line:sub(j, j):match("%d") do j = j + 1 end
            end
            local num = line:sub(i, j - 1)
            table.insert(tokens, {cls = (num:find("%.") and "fl" or "dv"), text = num})
            i = j
        elseif c:match("%a") or c == "_" then
            local j = i
            while j <= n and (line:sub(j, j):match("%w") or line:sub(j, j) == "_") do
                j = j + 1
            end
            local word = line:sub(i, j - 1)
            local cls
            if T_KEYWORDS[word] then
                cls = "cf"
            elseif T_CONSTANTS[word] then
                cls = "cn"
            elseif line:sub(j, j) == "(" then
                cls = "fu"
            end
            table.insert(tokens, {cls = cls, text = word})
            i = j
        elseif c == "." and line:sub(i + 1, i + 1):match("%a") then
            local j = i + 1
            while j <= n and (line:sub(j, j):match("%w") or line:sub(j, j) == "_") do
                j = j + 1
            end
            table.insert(tokens, {cls = nil, text = line:sub(i, j - 1)})
            i = j
        else
            local op = match_operator(line, i)
            if op then
                table.insert(tokens, {cls = "sc", text = op})
                i = i + #op
            else
                table.insert(tokens, {cls = nil, text = c})
                i = i + 1
            end
        end
    end

    local merged = {}
    for _, tok in ipairs(tokens) do
        local last = merged[#merged]
        if tok.cls == nil and last and last.cls == nil then
            last.text = last.text .. tok.text
        else
            table.insert(merged, {cls = tok.cls, text = tok.text})
        end
    end

    return merged
end

local function highlight_t(text)
    local html_lines = {}
    local latex_lines = {}

    for _, line in ipairs(split_lines(text)) do
        local html_parts = {}
        local latex_parts = {}
        for _, tok in ipairs(tokenize_line(line)) do
            if tok.cls == nil then
                table.insert(html_parts, escape_map(tok.text, HTML_ESCAPES))
                table.insert(latex_parts,
                    "\\NormalTok{" .. escape_map(tok.text, LATEX_ESCAPES) .. "}")
            else
                table.insert(html_parts,
                    string.format('<span class="%s">%s</span>',
                                   tok.cls, escape_map(tok.text, HTML_ESCAPES)))
                table.insert(latex_parts,
                    "\\" .. LATEX_TOK_CMD[tok.cls] .. "{"
                        .. escape_map(tok.text, LATEX_ESCAPES) .. "}")
            end
        end
        table.insert(html_lines, table.concat(html_parts))
        table.insert(latex_lines, table.concat(latex_parts))
    end

    local html = "<pre class=\"t\"><code>" .. table.concat(html_lines, "\n") .. "</code></pre>"
    local latex = "\\begin{Shaded}\n\\begin{Highlighting}[]\n"
        .. table.concat(latex_lines, "\n")
        .. "\n\\end{Highlighting}\n\\end{Shaded}"

    return pandoc.RawBlock("html", html), pandoc.RawBlock("latex", latex)
end

function CodeBlock(el)
    if not (has_class(el, "t") or has_class(el, "tlang")) then return nil end

    local options, body = parse_chunk_options(el.text)
    local include = normalize_bool(options.include, true)
    local should_eval = normalize_bool(options.eval, true)
    local show_code = normalize_bool(options.echo, true)
    local results = options.results and trim(options.results):lower() or nil
    local show_output = include and normalize_bool(options.output, true) and
                            results ~= "hide"

    if trim(body) == "" then
        local rendered_blocks = {}

        -- For chunks that only contain options (#| lines) and no body:
        -- - respect include/echo
        -- - do not re-emit the original block (which would include #| lines)
        if include and show_code then
            table.insert(rendered_blocks, pandoc.CodeBlock("", el.attr))
        end

        return rendered_blocks
    end

    local rendered_blocks = {}

    if include and show_code then
        local html_block, latex_block = highlight_t(body)
        table.insert(rendered_blocks, html_block)
        table.insert(rendered_blocks, latex_block)
    end

    if not should_eval then return rendered_blocks end

    -- Build the new session source incrementally without rebuilding all chunks
    local new_session_source
    if t_state.session_source == "" then
        new_session_source = body
    else
        new_session_source = t_state.session_source .. "\n\n" .. body
    end

    local ok, output = execute_t_unsafe(new_session_source)
    if not ok then
        if include then
            table.insert(rendered_blocks, render_error(output))
            return rendered_blocks
        end
        return {}
    end

    -- Only update the session state after successful execution
    t_state.session_source = new_session_source

    if show_output then
        local output_block = make_output_block(output)
        if output_block ~= nil then
            table.insert(rendered_blocks, output_block)
        end
    end

    return rendered_blocks
end
