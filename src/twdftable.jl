defaultTreeHelpText = """
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
Home       : jump to the start
End        : jump to the end
ctrl_left/right arrow: paginate to left/right
[, ]       : make current column narrower/wider
ctrl_up    : move up to the start of the current branch or previous branch
ctrl_down  : move up to the next branch
_          : collapse all
/          : search dialog
F2         : Change pivot
F3         : Change columns/order
F6         : popup window for value
n, p       : Move to next/previous matched line
"""

type FormatHints
    width         :: Int  # column width, not the format width
    scale         :: Real
    precision     :: Int
    commas        :: Bool
    stripzeros    :: Bool
    parens        :: Bool
    rednegative   :: Bool # print in red when negative?
    hidezero      :: Bool
    alternative   :: Bool
    mixedfraction :: Bool
    conversion    :: ASCIIString
end

function FormatHints{T<:Integer}( ::Type{T} )
    FormatHints( 10, 1, 0, true, false, false, true, true, false, false, "d" )
end
function FormatHints{T<:Unsigned}( ::Type{T} )
    FormatHints( 8, 1, 0, true, false, false, true, true, false, false, "x" )
end
function FormatHints{T<:FloatingPoint}( ::Type{T} )
    FormatHints( 10, 1.0, 2, true, false, false, true, true, false, false, "f" )
end
function FormatHints{T<:Rational}( ::Type{T} )
    FormatHints( 12, 1, 0, false, false, false, true, true, false, true, "s" )
end
#TODO: date
function FormatHints( ::Type{} )
    FormatHints( 14, 1, 0, false, false, false, true, true, false, false, "s" )
end

function applyformat{T<:Number}( v::T, fmt::FormatHints )
    if fmt.hidezero && v == 0
        ""
    else
        format( v * fmt.scale,
            precision     = fmt.precision,
            commas        = fmt.commas,
            stripzeros    = fmt.stripzeros,
            parens        = fmt.parens,
            alternative   = fmt.alternative,
            mixedfraction = fmt.mixedfraction,
            conversion    = fmt.conversion
            )
    end
end

#=
@doc """
Facilities to help map GUI input / expression into a function that aggregates columns.
We would store that function and use it whenever we need to aggregate a column.

Three ways to instantiate the DataFrameAggr
* String: either a simple name "mean", or an expression wmean( :col, :WeightColumn )
* Similarly, Symbol or expression, such as :mean, or :( wmean( :col, :WeightColumn ) )
    * if just a simple name, it is assumed to be a function, we would try these signature
        * f( x::DataArray ) -> output is the aggregated scalar
        * f( x::Dataframe ) -> output is the aggregated scalar, rare.
    * if expression, it must be of the form
        * f( args..., kw1=v1, kw2=v2, ... )
        * straightforward symbols are expected to be column names
""" ->
=#
immutable DataFrameAggr
    f::Function
    sig::Any
end

DataFrameAggrCache = Dict{Any, DataFrameAggr}()

DataFrameAggr() = DataFrameAggr( _->NA, (DataArray,) )

function DataFrameAggr( x::String )
    global DataFrameAggrCache
    if haskey( DataFrameAggrCache, x )
        return DataFrameAggrCache[ x ]
    end
    ex = parse( x )
    ret = DataFrameAggr( ex )
    DataFrameAggrCache[x] = ret
    ret
end

function DataFrameAggr( ex::Union( Expr, Symbol ) )
    global DataFrameAggrCache
    if haskey( DataFrameAggrCache, ex )
        return DataFrameAggrCache[ ex ]
    end

    if typeof( ex ) == Symbol
        # assume it is a function, e.g. mean, std, uniq, countuniq, etc.
        if contains( string(ex), "!" )
            error( string(ex) * " seems to have side effects" )
        end
        if ex == :NA
            return ( DataFrameAggrCache[ex] = DataFrameAggr() )
        end
        v = nothing
        try
            v = eval( Main, ex )
        end
        if typeof( v ) != Function
            error( string( ex ) * " does not represent a function" )
        end
        ex = :( $ex() )
    else
        if !isexpr( ex, :call )
            error( string( ex ) * " does not look like an aggregator function")
        end
        # disallow mutating function
        fname = ex.args[1]
        if Base.Meta.isexpr( fname, :curly )
            error( "DataFrameAggr: curly not supported")
        elseif !( typeof( fname ) <: Symbol )
            error( "DataFrameAggr: only simple function name please")
        end
        if contains( string(fname), "!" )
            error( string(fname) * " seems to have side effects" )
        end
        v = nothing
        try
            v = eval( Main, fname )
        end
        if typeof( v ) != Function
            error( string( fname ) * " does not represent a function" )
        end
    end

    mt = methods( v )
    for m in mt
        if isempty( m.sig )
            continue
        end
        # count the non-kw signatures
        nargs = 0
        for i = 2:length( ex.args )
            if !isexpr( ex.args[i], [ :parameters, :kw ] )
                nargs += 1
            end
        end
        if typeof( m.sig[1] ) <: Tuple
            continue
        end
        if typeof( m.sig[1] ) <: UnionType
            continue
        end
        if in( m.sig[1].name.name, [ :DataArray, :PooledDataArray, :AbstractDataArray ] ) && nargs == 0
            ex2 = deepcopy( ex )
            insert!( ex2.args, 2, :_ )
            l = eval( Main,Expr( :(->), :_, ex2 ) )
            return ( DataFrameAggrCache[ex] = DataFrameAggr( l, (DataArray,) ) )
        elseif in( m.sig[1].name.name,[:DataFrame, :AbstractDataFrame] )
            ex2 = deepcopy( ex )
            insert!( ex2.args, 2, :_ )
            l = eval( Main,Expr( :(->), :_, ex2 ) )
            return ( DataFrameAggrCache[ex] = DataFrameAggr( l, (DataFrame,) ) )
        end
    end
    error( "No usable method. Accepts (DataArray/PDA,) or (DataFrame,args...)" )
end

function DataFrameAggr( ::Type{} )
    DataFrameAggr( "uniqvalue" )
end

function DataFrameAggr{T<:Real}( ::Type{T} )
    DataFrameAggr( "sum" )
end

function uniqvalue( x::AbstractDataArray; skipna::Bool=true )
    levels = DataArrays.levels(x)
    if skipna
        l = dropna( levels )
        if length(l) == 1
            return l[1]
        end
        return NA
    end
    if length(levels) == 1
        return levels[1]
    end
    return NA
end

function uniqvalue{T<:String}( x::Union( DataArray{T}, PooledDataArray{T} ); skipna::Bool=true, skipempty::Bool=true )
    levels = DataArrays.levels(x)
    if skipna
        l = dropna( levels )
        if skipempty
            emptyidx = findfirst( l, "" )
            if length( l ) == 1 && emptyidx == 0
                return l[1]
            elseif length( l ) == 2 && emptyidx != 0
                if emptyidx == 1
                    return l[2]
                else
                    return l[1]
                end
            end
        elseif length( l ) == 1
            return l[1]
        end
        return NA
    end
    if skipempty
        emptyidx = findfirst( levels, "" )
        if length( levels ) == 1 && emptyidx == 0
            return levels[1] # could be NA
        elseif length( levels ) == 2 && emptyidx != 0
            if emptyidx == 1
                return levels[2]
            else
                return levels[1]
            end
        end
    elseif length( levels ) == 1
        return levels[1]
    end
    return NA
end

type TwTableColInfo
    name::Symbol
    displayname::UTF8String
    visible::Bool
    format::FormatHints
    aggr::DataFrameAggr
end

type TwDfTableNode
    parent::WeakRef
    context::WeakRef
    pivotcols::Array{ Symbol, 1 }
    pivotvals::Tuple
    isOpen::Bool
    children::Array{ Any, 1} # only root node can have empty children
    subdataframe::Any
    subdataframesorted::Any
    colvalcache::Dict{ Symbol, Any } # order indep aggregated values
    function TwDfTableNode()
        new( WeakRef(), WeakRef(), Symbol[], (), false, Any[], nothing, nothing, Dict{Symbol,Any}() )
    end
    function TwDfTableNode( p::TwDfTableNode )
        x = TwDfTableNode()
        x.parent = WeakRef( p )
        x.context = p.context
        x
    end
end

function getindex( n::TwDfTableNode, c::Symbol )
    if haskey( n.colvalcache, c )
        return n.colvalcache[ c ]
    else
        context = n.context.value
        aggr = context.allcolInfo[ c ].aggr
        if aggr.sig == (DataArray,)
            ret = aggr.f( n.subdataframe[ c ] )
        elseif aggr.sig == (DataFrame,)
            ret = aggr.f( n.subdataframe )
        end
        if typeof( ret ) <: AbstractDataFrame
            ret = ret[1][1] # first col, first row
        end

        n.colvalcache[c] = ret
        return ret
    end
end

# this is the widget data. all subnodes hold a weakref back to this to
# facilitate aggregation, ordering and output
type TwDfTableData
    rootnode::TwDfTableNode
    pivots::Array{ Symbol, 1 }
    sortorder::Array{ (Symbol, Symbol), 1 } # [ (:col1, :asc ), (:col2, :desc), ... ]
    datalist::Array{Any, 1} # (tuple{symbol}, 0) -> node, (tuple{symbol},#) -> row within that sub-df
    datalistlen::Int
    datatreewidth::Int
    headerlines::Int # how many lines does the header occupy, usually just 1
    currentTop::Int
    currentLine::Int
    currentCol::Int
    currentLeft::Int
    currentRight::Int # right most visible column
    colInfo::Array{ TwTableColInfo, 1 } # only the visible ones
    allcolInfo::Dict{ Symbol, TwTableColInfo } # including invisible ones
    bottomText::String
    helpText::String
    searchText::String
    # calculated dimension
    TwDfTableData() = new( TwDfTableNode(),
        Symbol[], (Symbol,Symbol)[], Any[], 0, 10, 1, 1, 1, 1, 1, 1, TwTableColInfo[],
        Dict{Symbol,TwTableColInfo}(), "", defaultTreeHelpText, "" )
end

#TODO: allow Regex in formatHints and aggrHints
function newTwDfTable( scr::TwScreen, df::DataFrame, h::Real,w::Real,y::Any,x::Any;
        pivots = Symbol[],
        colorder = Any[ "*" ], # mix of symbol, regex, and "*" (the rest), "*" can be in the middle
        hidecols = Any[], # anything here trumps colorder, Symbol, or Regex
        title = "DataFrame",
        formatHints = Dict{Any,FormatHints}(), # Symbol/Type -> FormatHints
        aggrHints = Dict{Any,DataFrameAggr}(), # Symbol/Type -> DataFrameAggr
        headerHints = Dict{Symbol,UTF8String}(),
        bottomText = "F1: help" )
    obj = TwObj( twFuncFactory( :DfTable ) )
    registerTwObj( scr, obj )
    obj.value = df
    obj.title = title
    obj.box = true
    obj.borderSizeV= 1
    obj.borderSizeH= 2
    obj.data = TwDfTableData()
    obj.data.rootnode.subdataframe = df
    obj.data.rootnode.context = WeakRef( obj.data )
    obj.data.pivots = pivots
    expandnode( obj.data.rootnode )
    builddatalist( obj.data )

    # construct visible columns in the right order
    function move_columns( targetarray::Array{ Symbol,1 }, sourcearray::Array{Any,1}, remaincols::Array{Symbol,1} )
        local i = 1
        local n = length( sourcearray )
        while !isempty( remaincols ) && i <= n
            local s = sourcearray[i]
            if s == "*"
                error( "illegal extra *")
            elseif typeof( s ) == Regex
                j = 1
                while j <= length( remaincols )
                    if match( s, string( remaincols[j] ) ) != nothing
                        push!( targetarray, remaincols[j] )
                        deleteat!( remaincols, j )
                        continue
                    end
                    j += 1
                end
            elseif typeof( s ) == Symbol
                if !in( s, remaincols )
                    error( "Column " * string( s ) * " not in " * string( remaincols )  * " src:" * string( sourcearray ) )
                end
                push!( targetarray, s )
                local idx = findfirst( remaincols, s )
                deleteat!( remaincols, idx )
            else
                error( "illegal " * string( s ) * " found" )
            end

            i += 1
        end
    end

    remaincols = names( df )
    if in( "*", colorder )
        colspreast = Symbol[]
        colspostast = Symbol[]
        local idx = findfirst( colorder, "*" )
        move_columns( colspreast, colorder[ 1:(idx-1) ], remaincols )
        finalcolorder = colspreast
        move_columns( colspostast, colorder[ (idx+1):length( colorder ) ], remaincols )
        append!( finalcolorder, remaincols )
        append!( finalcolorder, colspostast )
    else
        finalcolorder = Symbol[]
        move_columns( finalcolorder, colorder, remaincols )
    end

    # remove anything in hidecols
    removed = Symbol[]
    move_columns( removed, hidecols, finalcolorder )

    # construct colInfo for each col in finalcolorder
    for c in finalcolorder
        t = eltype( df[ c ] )
        hdr = get( headerHints, c, string( c ) )
        fmt = get( formatHints, c,
                get( formatHints, t, FormatHints( t ) ) )
        agr = get( aggrHints, c,
                get( aggrHints, t, DataFrameAggr( t ) ) )
        ci = TwTableColInfo( c, hdr, true, fmt, agr )
        push!( obj.data.colInfo, ci )
        obj.data.allcolInfo[ c ] = ci
    end

    updateTableDimensions( obj )
    obj.data.bottomText = bottomText
    alignxy!( obj, h, w, x, y )
    configure_newwinpanel!( obj )
    obj
end

function expandnode( n::TwDfTableNode )
    if n.isOpen # nothing to do
        return
    end
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    if length( npivots ) < length( pivots ) # populate children nodes
        if isempty( n.children )
            nextpivots = deepcopy( npivots )
            push!( nextpivots, pivots[ length( npivots )+1 ] )
            gd = groupby( n.subdataframe, nextpivots )
            for g in gd
                dfr = DataFrameRow( g[ gd.cols ], 1 )
                valtuple = tuple( [ x[2] for x in dfr ]... )
                r = TwDfTableNode( n )
                r.pivotcols = nextpivots
                r.pivotvals = valtuple
                r.subdataframe = g
                push!( n.children, r )
            end
        end
    end
    ordernode( n )
    n.isOpen = true
end

# order the children, or if the terminal node, order the subdataframe
# also order opened children (recursive)
function ordernode( n::TwDfTableNode )
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    sortorder = n.context.value.sortorder
    if length( npivots ) < length( pivots ) # populate children nodes
        sort!( n.children, lt = (x,y) -> begin
            for sc in sortorder
                if x[sc[1]] == y[sc[1]]
                    continue
                end

                if sc[2] == :desc
                    return y[sc[1]] < x[sc[1]]
                else
                    return x[sc[1]] < y[sc[1]]
                end
            end
            return false
        end )
        for c in n.children
            if c.isOpen
                ordernode( c )
            end
        end
    else
        if length( sortorder ) == 0
            n.subdataframesorted = n.subdataframe
        else
            n.subdataframesorted = sort(n.subdataframe,
                cols=( map( _->_[1], sortorder)...),
                rev=( map(_->_[2]==:desc, sortorder )... ) )
        end
    end
end

function builddatalist( o::TwDfTableData )
    o.datalist = Any[]
    pivots = o.pivots

    function presublist( subn::TwDfTableNode, substack::Array{Int,1}, skiplines::Array{Int,1}, islast::Bool )
        if islast
            newskip = copy(skiplines)
            push!( newskip, length(substack))
            sublist( subn, substack, newskip )
        else
            sublist( subn, substack, skiplines )
        end
    end

    function sublist( n::TwDfTableNode, stack::Array{Int,1}, skiplines::Array{Int,1} )
        if isempty( n.pivotvals )
            name = "Root"
        else
            name = string( n.pivotvals[end] )
        end

        push!( o.datalist, ( name, stack, n.isOpen ? :open : :close, skiplines, n ) )
        if n.isOpen
            if length( n.pivotcols ) < length( pivots )
                len = length( n.children )
                for (i,c) in enumerate( n.children )
                    substack = copy( stack )
                    push!( substack, i )
                    presublist( c, substack, skiplines, i==len )
                end
            else
                for i in 1:size( n.subdataframe,1 )
                    substack = copy( stack )
                    push!( substack, i )
                    push!( o.datalist, ( string(i), substack, :single, skiplines, n ) )
                end
            end
        end
    end

    sublist( o.rootnode, Int[], Int[] )
    o.currentLine = min( o.currentLine, length( o.datalist ) )
end

function updateTableDimensions( o::TwObj )
    global treeTypeMaxWidth, treeValueMaxWidth

    o.data.datalistlen = length( o.data.datalist )
    o.data.headerlines = maximum( map( x->length( split( x.displayname, "\n" ) ), o.data.colInfo ) )
    # reminder: (name, stack, exphints, skiplines, node )
    o.data.datatreewidth = maximum( map( d -> 2*(length(d[2])+1) + length(d[1])+1,
        o.data.datalist ) )
end

function drawTwDfTable( o::TwObj )
    updateTableDimensions( o )
    viewContentHeight = o.height - 2 * o.borderSizeV - o.data.headerlines
    viewContentWidth  = o.width - 2 * o.borderSizeH

    box( o.window, 0,0 )
    if !isempty( o.title )
        titlestr = o.title
        mvwprintw( o.window, 0, int( ( o.width - length(titlestr) )/2 ), "%s", titlestr )
    end
    if o.data.datalistlen <= viewContentHeight
        info = "ALL"
    else
        info = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.datalistlen,
            o.data.currentLine / o.data.datalistlen * 100 )
    end
    mvwprintw( o.window, 0, o.width - length(info)-3, "%s", info )
    updateTableDimensions( o )

    # header row(s)
    wattron( o.window, COLOR_PAIR(3) )
    startx = 1+o.data.datatreewidth
    lastcol = 1
    lastwidth = 8
    for col = o.data.currentLeft:length( o.data.colInfo )
        if startx > viewContentWidth
            break
        end
        ci = o.data.colInfo[col]
        lines = split( ci.displayname, "\n" )
        nlines= length(lines)
        width = ci.format.width

        islastcol = ( startx+width+1 > viewContentWidth ) || col == length( o.data.colInfo )
        if islastcol
            width = min( width, viewContentWidth-startx )
        end
        o.data.currentRight = lastcol = col
        lastwidth = width

        if o.data.currentCol == col
            wattron( o.window, A_BOLD )
        end
        for (i,line) in enumerate( lines )
            s = ensure_length( line, width )
            mvwprintw( o.window, i+(o.data.headerlines-nlines), startx, "%s", s )
        end
        if o.data.currentCol == col
            wattroff( o.window, A_BOLD )
        end
        if !islastcol
            for i = 1:o.data.headerlines
                mvwaddch( o.window, i, startx+width, get_acs_val( 'x' ) )
            end
        end
        startx += width + 1
    end
    wattroff( o.window, COLOR_PAIR(3) )
    # reminder: (name, stack, exphints, skiplines, node )
    for r in o.data.currentTop:min( o.data.currentTop + viewContentHeight - 1, o.data.datalistlen )
        stacklen = length( o.data.datalist[r][2])

        # treecolume is always shown
        s = ensure_length( repeat( " ", 2*stacklen + 1) * o.data.datalist[r][1], o.data.datatreewidth-2 )

        if r == o.data.currentLine
            wattron( o.window, A_BOLD | COLOR_PAIR(15) )
        end
        mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2, "%s", s )
        for i in 1:stacklen - 1
            if !in( i, o.data.datalist[r][4] ) # skiplines
                mvwaddch( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*i, get_acs_val( 'x' ) ) # vertical line
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t') # tee pointing right
            if r == o.data.datalistlen ||  # end of the whole thing
                length(o.data.datalist[r+1][2]) < stacklen || # next one is going back in level
                ( length(o.data.datalist[r+1][2]) > stacklen && in( stacklen, o.data.datalist[r+1][4] ) ) # going deeper in level
                contchar = get_acs_val( 'm' ) # LL corner
            end
            mvwaddch( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen, contchar )
            mvwaddch( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen+1, get_acs_val('q') ) # horizontal line
        end
        if o.data.datalist[r][3] == :close
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( char( 0x25b8 ) ) ) # right-pointing small triangle
        elseif o.data.datalist[r][3] == :open
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( char( 0x25be ) ) ) # down-pointing small triangle
        end

        if r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR(15) )
        end
        mvwaddch( o.window, o.data.headerlines+1+r-o.data.currentTop, o.data.datatreewidth, get_acs_val( 'x' ) )

        # other columns
        # get the node or DataFrameRow first
        node = o.data.datalist[r][5]
        startx = 1+o.data.datatreewidth
        for col = o.data.currentLeft:lastcol
            cn = o.data.colInfo[ col ].name
            if o.data.datalist[r][3] != :single # just the node
                v = node[ cn ]
            else
                v = node.subdataframesorted[ cn ][ o.data.datalist[r][2][end] ]
            end
            width = ( col == lastcol ? lastwidth : o.data.colInfo[ col ].format.width )
            isred = false
            if typeof( v ) == NAtype
                str = ensure_length( "", width )
            elseif typeof( v ) <: Real
                str = applyformat( v, o.data.colInfo[col].format )
                if length(str) > width # all ####
                    str = repeat( "#", width )
                elseif length(str) < width
                    str = repeat( " ", width - length(str) ) * str
                end
                isred =  v < 0
            elseif typeof( v ) <: String
                str = ensure_length( v, width )
            else
                str = ensure_length( string(v), width )
            end
            if col == o.data.currentCol && r == o.data.currentLine
                wattron( o.window, A_BOLD | COLOR_PAIR(15) )
            end
            if isred
                wattron( o.window, COLOR_PAIR( 1 ) )
            end
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, startx, "%s", str )
            if isred
                wattroff( o.window, COLOR_PAIR( 1 ) )
            end
            if col == o.data.currentCol && r == o.data.currentLine
                wattroff( o.window, A_BOLD | COLOR_PAIR(15) )
            end
            if col != lastcol
                mvwaddch( o.window, o.data.headerlines + 1+ r-o.data.currentTop, startx+width, get_acs_val( 'x' ) )
            end
            startx += width + 1
        end
    end
    if length( o.data.bottomText ) != 0 && o.box
        mvwprintw( o.window, o.height-1, int( (o.width - length(o.data.bottomText))/2 ), "%s", o.data.bottomText )
    end
end

function injectTwDfTable( o::TwObj, token::Any )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight = o.height - 2 * o.borderSizeV - o.data.headerlines
    viewContentWidth = o.width - 2* o.borderSizeH - o.data.datatreewidth
    widths = map( x->x.format.width, o.data.colInfo )

    update_tree_data = ()->begin
        builddatalist( o.data )
    end

    checkTop = () -> begin
        if o.data.currentTop < 1
            o.data.currentTop = 1
        elseif o.data.currentTop > o.data.datalistlen - viewContentHeight + 1
            o.data.currentTop = max(1,o.data.datalistlen - viewContentHeight + 1)
        end
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > viewContentHeight-1
            o.data.currentTop = o.data.currentLine - viewContentHeight+1
        end
    end
    checkLeft = () -> begin
        if o.data.currentLeft < 1
            o.data.currentLeft = 1
        else # check if we have enough width to show from currentLeft to currentCol
            revcumwidths = cumsum( map( x->x+1, reverse( widths ) ) ) # with boundary
            widthrng = searchsorted( revcumwidths, viewContentWidth )
            if o.data.currentLeft > length( o.data.colInfo ) - widthrng.stop +1
                o.data.currentLeft = length( o.data.colInfo ) - widthrng.stop +1
            end
        end
        if o.data.currentLeft > o.data.currentCol
            o.data.currentLeft = o.data.currentCol
        else
            revcumwidths = cumsum( map( x->x+1, reverse( widths[o.data.currentLeft:o.data.currentCol] ) ) ) # with boundary
            widthrng = searchsorted( revcumwidths, viewContentWidth )
            if o.data.currentLeft < o.data.currentCol - widthrng.stop +1
                o.data.currentLeft = o.data.currentCol - widthrng.stop +1
            end
        end
    end
    movevertical = n -> begin
        oldline = o.data.currentLine
        o.data.currentLine = max(1, min( o.data.datalistlen, o.data.currentLine + n) )
        if oldline != o.data.currentLine
            checkTop()
            return true
        else
            beep()
            return false
        end
    end
    movehorizontal = n -> begin
        oldcol = o.data.currentCol
        o.data.currentCol = max(1, min( length( o.data.colInfo ), o.data.currentCol + n) )
        if oldcol != o.data.currentCol
            checkLeft()
            return true
        else
            beep()
            return false
        end
    end

    # reminder: (name, stack, exphints, skiplines, node )
    if token == :esc
        retcode = :exit_nothing
    elseif ( token == " " || token == symbol( "return" ) || token == :enter ) && o.data.datalist[ o.data.currentLine ][3] != :single
        expandhint = o.data.datalist[ o.data.currentLine ][3]
        node = o.data.datalist[ o.data.currentLine][5]
        if node.isOpen
            node.isOpen = false
        else
            expandnode( node )
        end
        update_tree_data()
        dorefresh = true
    elseif token == "_"
        currentstack = copy(o.data.datalist[ o.data.currentLine ][4])
        if length( currentstack ) > 1
            currentstack = Any[ currentstack[1] ]
        end
        o.data.openstatemap = Dict{Any,Bool}()
        o.data.openstatemap[ Any[] ] = true
        update_tree_data()
        prevline = o.data.currentLine
        o.data.currentLine = 1
        for i in 1:min(prevline,o.data.datalistlen)
            if currentstack == o.data.datalist[ i ][4]
                o.data.currentLine = i
                if abs( i-prevline ) > viewContentHeight
                    o.data.currentTop = o.data.currentLine - int(viewContentHeight / 2)
                end
                break
            end
        end
        checkTop()
        dorefresh = true
    elseif token == :up
        dorefresh = movevertical(-1)
    elseif token == :down
        dorefresh = movevertical(1)
    elseif token == :left
        dorefresh = movehorizontal(-1)
    elseif token == :ctrl_left
        if o.data.currentCol != o.data.currentLeft
            o.data.currentCol = o.data.currentLeft
            dorefresh = true
        elseif o.data.currentLeft == 1
            beep()
        else
            # page left
            revcumwidths = cumsum( map( x->x+1, reverse( widths[1:o.data.currentLeft] ) ) ) # with boundary
            widthrng = searchsorted( revcumwidths, o.data.datatreewidth )
            o.data.currentLeft = o.data.currentCol = o.data.currentLeft - widthrng.start + 1
            checkLeft()
        end
    elseif token == :right
        dorefresh = movehorizontal(1)
    elseif token == :ctrl_right
        if o.data.currentCol != o.data.currentRight
            o.data.currentCol = o.data.currentRight
            dorefresh = true
        elseif o.data.currentRight == length( o.data.colInfo )
            beep()
        else
            cumwidths = cumsum( map( x->x+1, reverse( widths[o.data.currentRight:end] ) ) ) # with boundary
            widthrng = searchsorted( cumwidths, o.data.datatreewidth )
            o.data.currentRight = o.data.currentCol = o.data.currentRight + widthrng.stop
            checkLeft()
        end
    elseif token == :pageup
        dorefresh = movevertical( -viewContentHeight + o.data.headerlines)
    elseif token == :pagedown
        dorefresh = movevertical( viewContentHeight - o.data.headerlines )
    elseif  token == :home
        if o.data.currentTop != 1 || o.data.currentLeft != 1 || o.data.currentLine != 1 || o.data.currentCol != 1
            o.data.currentTop = 1
            o.data.currentLeft = 1
            o.data.currentLine = 1
            o.data.currentCol = 1
            dorefresh = true
        else
            beep()
        end
    elseif in( token, Any[ symbol("end") ] )
        if o.data.currentTop + viewContentHeight -1 < o.data.datalistlen
            o.data.currentTop = o.data.datalistlen - viewContentHeight + 1
            o.data.currentLine = o.data.datalistlen
            dorefresh = true
        else
            beep()
        end
    elseif token == "["
        width = o.data.colInfo[ o.data.currentCol ].format.width
        if width > 4
            width -=1
            o.data.colInfo[ o.data.currentCol ].format.width = width
            dorefresh = true
        else
            beep()
        end
    elseif token == "]"
        width = o.data.colInfo[ o.data.currentCol ].format.width
        if width < viewContentHeight-1
            width +=1
            o.data.colInfo[ o.data.currentCol ].format.width = width
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_down
    elseif token == :ctrl_up
    elseif token == :F1
        helper = newTwViewer( o.screen.value, o.data.helpText, :center, :center, showHelp=false, showLineInfo=false, bottomText = "Esc to continue" )
        activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        dorefresh = true
        #TODO search, jump to line, etc.
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end
