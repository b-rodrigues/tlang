# dump_symbols.jl <dir>: differential fixture driver for T's Julia
# dependency scanner (see tests/test_julia_diff.ml).
#
# For every case_*.jl file in <dir> (sorted), parses the whole file
# with Julia's own parser and prints one tab-separated line:
#   <stem>\t<sorted unique symbols>
# Symbols are all Symbol leaves (expression heads excluded), unwrapped
# from QuoteNode, with leading @ stripped (macros) and only
# identifier-shaped names kept. Strings, chars, comments, numbers and
# keywords-as-heads therefore never appear -- exactly the set of names
# really present in code. T's scanner must show every one of them;
# anything T misses is a dropped read (the silent direction).
# Base Julia only: no packages, so startup stays fast.

function syms(x, acc)
    if x isa Symbol
        s = String(x)
        if startswith(s, "@") && length(s) > 1
            s = s[2:end]
        end
        if occursin(r"^[\p{L}_][\p{L}\p{N}_!]*$", s)
            push!(acc, s)
        end
    elseif x isa QuoteNode
        syms(x.value, acc)
    elseif x isa Expr
        for a in x.args
            syms(a, acc)
        end
    end
    return acc
end

function main()
    dir = ARGS[1]
    files = sort!(filter!(f -> startswith(basename(f), "case_") && endswith(f, ".jl"), readdir(dir; join=true)))
    for path in files
        stem = splitext(basename(path))[1]
        code = read(path, String)
        tree = Meta.parseall(code; filename=path)
        out = sort!(unique!(syms(tree, String[])))
        println(stem, "\t", join(out, " "))
    end
end

main()
