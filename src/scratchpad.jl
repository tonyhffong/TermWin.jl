const _SCRATCHPAD = Dict{String,Any}()

function pin!(name::AbstractString, value)
    _SCRATCHPAD[String(name)] = value
end

function unpin!(name::AbstractString)
    delete!(_SCRATCHPAD, String(name))
end

function scratchpad_dict()
    _SCRATCHPAD
end

function export_to_main!(name::String)
    haskey(_SCRATCHPAD, name) || return
    Core.eval(Main, Expr(:(=), Symbol(name), QuoteNode(_SCRATCHPAD[name])))
end

function scratchpad_isempty()
    isempty(_SCRATCHPAD)
end
