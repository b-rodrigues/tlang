# dump_symbols.jl <dir>: differential fixture driver for T's Julia
# dependency scanner (see tests/test_julia_diff.ml).
#
# For every case_*.jl file in <dir> (sorted), parses the whole file
# with Julia's own parser and prints two tab-separated lines:
#   <stem>\t<sorted unique symbols>
#   <stem>@binds\t<sorted unique top-level binds>
# Symbols are all Symbol leaves (expression heads excluded), unwrapped
# from QuoteNode, with leading @ stripped (macros) and only
# identifier-shaped names kept. Strings, chars, comments, numbers and
# keywords-as-heads therefore never appear -- exactly the set of names
# really present in code. T's scanner must show every one of them;
# anything T misses is a dropped read (the silent direction).
# Binds are names bound unconditionally at top level: plain `=` with a
# Symbol target directly under toplevel/block (begin/end is
# transparent), plus definition names (function/macro/struct/module/
# abstract/primitive, including short-form `g(p) = ...`). Anything
# inside function/if/for/while/try/catch/finally/let/quote/do bodies,
# comprehensions, or module/struct bodies never binds outward. `for`
# loop variables never bind. T must not bind more than this set;
# over-binding drops a later read and loses an edge.
# Known narrow spots (false-failure direction only, never missed
# bugs): `struct Foo <: Bar` hides the name in Expr(:<:),
# chained `x = y = 1` keeps only `x`, tuple targets are skipped.
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

function ident_ok(s)
    return occursin(r"^[\p{L}_][\p{L}\p{N}_!]*$", s)
end

function defname(x)
    if x isa Symbol
        s = String(x)
        return ident_ok(s) ? s : nothing
    elseif x isa Expr && x.head == :call && length(x.args) >= 1
        return defname(x.args[1])
    elseif x isa Expr && (x.head == :where || x.head == :(::))
        for a in x.args
            n = defname(a)
            if n !== nothing
                return n
            end
        end
        return nothing
    else
        return nothing
    end
end

function first_sym(args)
    for a in args
        if a isa Symbol
            s = String(a)
            if ident_ok(s)
                return s
            end
        end
    end
    return nothing
end

function collect_binds(x, acc)
    if x isa Expr && (x.head == :toplevel || x.head == :block)
        for a in x.args
            collect_binds(a, acc)
        end
    elseif x isa Expr && x.head == :(=) && length(x.args) >= 1
        lhs = x.args[1]
        if lhs isa Symbol
            s = String(lhs)
            if ident_ok(s)
                push!(acc, s)
            end
        else
            n = defname(lhs)
            if n !== nothing
                push!(acc, n)
            end
        end
    elseif x isa Expr && (x.head == :function || x.head == :macro) && length(x.args) >= 1
        n = defname(x.args[1])
        if n !== nothing
            push!(acc, n)
        end
    elseif x isa Expr && (x.head == :struct || x.head == :module || x.head == :abstract || x.head == :primitive)
        n = first_sym(x.args)
        if n !== nothing
            push!(acc, n)
        end
    else
        return acc
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
        binds = sort!(unique!(collect_binds(tree, String[])))
        println(stem, "@binds\t", join(binds, " "))
    end
end

main()
