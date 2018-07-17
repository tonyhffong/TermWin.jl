defaultFuncHelpText = """
PgUp/PgDn  : method list navigation
Up/Dn      : method list navigation
Left/Right : search term cursor control
ctrl-a     : move cursor to start
ctrl-e     : move cursor to end
ctrl-k     : empty search entry
ctrl-r     : toggle insert/overwrite
Home       : jump to the start
End        : jump to the end
Shift-left/right : Navigate method list left and right
Ctrl-Sht-lft/rgt : Jump method list to left and right edge
F6         : explore Method as tree
F8         : edit method
"""

type TwFuncData
    datalist::Array{Any,1}
    datalistlen::Int
    datawidth::Int
    searchbox::Any
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::String
    showHelp::Bool
    helpText::String
    TwFuncData() = new( Method[], 0, 0, nothing,
        1, 1, 1, true, "", true, defaultFuncHelpText )
end

function argName(s, n)
    try
        return s.types[n]
    catch
        return argName(s.body, n)
    end
end

# the ways to use it:
# exact dimensions known: h,w,y,x, content to add later
# exact dimensions unknown, but content known and content drives dimensions
function newTwFunc( scr::TwObj, ms::Array{Method,1}; kwargs... )
    ns = String[] # names
    sig  = String[]
    files = String[]
    lines = Int[]
    for m in ms
        push!( ns, string( m.name ) )
        push!( sig, string( m.sig ) )
        tv, decls, file, line = Base.arg_decl_parts(m)
        push!( files, string( file ) )
        push!( lines, line )
    end
    df = DataFrame(
          name = ns,
          sig = sig,
          file = files,
          line = lines,
          nargs = Int[ m.nargs for m in ms ],
          arg1t = String[ (m.nargs>=1 ? ensure_length(string(argName(m.sig,1)),35,false) : "") for m in ms ],
          arg2t = String[ (m.nargs>=2 ? ensure_length(string(argName(m.sig,2)),35,false) : "") for m in ms ],
          arg3t = String[ (m.nargs>=3 ? ensure_length(string(argName(m.sig,3)),35,false) : "") for m in ms ]
          )
    colorder = extractkwarg!( kwargs, :colorder, [ :name, :sig, :nargs, "*" ] )
    pivots   = extractkwarg!( kwargs, :pivots, [ ] )
    aggrHints = extractkwarg!( kwargs, :aggrHints, @compat( Dict{Any,Any}(
        :nargs => :( uniqvalue ),
        :line => :( uniqvalue )
       ) ) )
    calcpivots = extractkwarg!( kwargs, :calcpivots, @compat( Dict{Symbol,Any}(
        :NArgsBuckets => CalcPivot( :( discretize( :nargs, [0,1,2,3,4]; boundedness= ^(:boundedbelow) ) ) )
       )))
    initdepth = extractkwarg!( kwargs, :initdepth, 2 )
    views = extractkwarg!( kwargs, :views, [
        @compat(Dict{Symbol,Any}( :name => "ByName", :pivots => [ :name] ) ),
        @compat(Dict{Symbol,Any}( :name => "ByNArgs", :pivots => [ :NArgsBuckets ] ) ),
        @compat(Dict{Symbol,Any}( :name => "By1StArgType", :pivots => [ :arg1t] ) ),
        @compat(Dict{Symbol,Any}( :name => "By2StArgType", :pivots => [ :arg2t] ) ),
        @compat(Dict{Symbol,Any}( :name => "By3StArgType", :pivots => [ :arg3t] ) )
    ] )
    widthHints = @compat( Dict{Symbol,Int}( :name => 10, :nargs => 5, :sig => 20, :file => 20, :line => 5 ) )
    obj = newTwDfTable( scr, df; colorder=colorder, pivots=pivots, aggrHints=aggrHints, calcpivots=calcpivots,
        widthHints=widthHints, initdepth=initdepth, views=views, kwargs... )
    obj.value = ms
    obj
end

function newTwFunc( scr::TwObj, mt::MethodTable; kwargs... )
    pivots   = extractkwarg!( kwargs, :pivots, [ :name, :arg1t ] )
    ms = Method[]
    d = start(mt)
    while !is(d,())
        push!( ms, d )
        d = d.next
    end
    obj = newTwFunc( scr, ms; kwargs... )
    obj.value = mt
    obj
end

function newTwFunc( scr::TwObj, f::Function; kwargs... )
    pivots   = extractkwarg!( kwargs, :pivots, [ :arg1t ] )
    obj = newTwFunc( scr, methods(f); pivots=pivots, kwargs... )
    obj.value = f
end
