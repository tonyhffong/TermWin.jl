# the ways to use it:
# exact dimensions known: h,w,y,x, content to add later
# exact dimensions unknown, but content known and content drives dimensions
function newTwFunc(scr::TwObj, ms::Array{Method,1}; kwargs...)
    ns = String[] # names
    sig = String[]
    files = String[]
    lines = Int[]
    for m in ms
        push!(ns, string(m.name))
        push!(sig, string(m.sig))
        push!(files, string(m.file))
        push!(lines, Int(m.line))
    end
    getparam(m, i) =
        (m.sig isa UnionAll || Any in m.sig.parameters) ? "" :
        (m.nargs >= i ? string(m.sig.parameters[i]) : "")
    df = DataFrame(
        name = ns,
        sig = sig,
        file = files,
        line = lines,
        nargs = Int[m.nargs for m in ms],
        arg1t = String[ensure_length(getparam(m, 1), 35, false) for m in ms],
        arg2t = String[ensure_length(getparam(m, 2), 35, false) for m in ms],
        arg3t = String[ensure_length(getparam(m, 3), 35, false) for m in ms],
    )
    colorder = extractkwarg!(kwargs, :colorder, [:name, :sig, :nargs, "*"])
    pivots = extractkwarg!(kwargs, :pivots, [])
    aggrHints = extractkwarg!(
        kwargs,
        :aggrHints,
        Dict{Any,Any}(:nargs => :(uniqvalue), :line => :(uniqvalue)),
    )
    calcpivots = extractkwarg!(
        kwargs,
        :calcpivots,
        Dict{Symbol,Any}(
            :NArgsBuckets => CalcPivot(
                :(discretize(:nargs, [0, 1, 2, 3, 4]; boundedness = ^(:boundedbelow))),
            ),
        ),
    )
    initdepth = extractkwarg!(kwargs, :initdepth, 2)
    views = extractkwarg!(
        kwargs,
        :views,
        [
            Dict{Symbol,Any}(:name => "ByName", :pivots => [:name]),
            Dict{Symbol,Any}(:name => "ByNArgs", :pivots => [:NArgsBuckets]),
            Dict{Symbol,Any}(:name => "By1StArgType", :pivots => [:arg1t]),
            Dict{Symbol,Any}(:name => "By2StArgType", :pivots => [:arg2t]),
            Dict{Symbol,Any}(:name => "By3StArgType", :pivots => [:arg3t]),
        ],
    )
    widthHints =
        Dict{Symbol,Int}(:name => 10, :nargs => 5, :sig => 20, :file => 20, :line => 5)
    obj = newTwDfTable(
        scr,
        df;
        colorder = colorder,
        pivots = pivots,
        aggrHints = aggrHints,
        calcpivots = calcpivots,
        widthHints = widthHints,
        initdepth = initdepth,
        views = views,
        kwargs...,
    )
    obj.value = ms
    obj
end

function newTwFunc(scr::TwObj, f::Function; kwargs...)
    pivots = extractkwarg!(kwargs, :pivots, [:arg1t])
    log("newTwFunc Function");
    obj = newTwFunc(scr, collect(methods(f)); kwargs...)
    obj.value = f
end
