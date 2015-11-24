defaultTableHelpText = """
PgUp/PgDn,
Arrow keys : standard navigation
<spc>,<rtn>: toggle leaf expansion
Home       : jump to the start
End        : jump to the end
ctrl_left/right arrow: paginate to left/right
[, ]       : make current column narrower/wider
ctrl_up    : move up to the start of the current branch or previous branch
ctrl_down  : move down to the next branch
+, -       : Expand or collapse 1 level everywhere
p          : Change pivot
c          : Change columns/order
v          : Switch preset views
/          : search text (on string columns) on exposed rows
?          : DEEP search text (on string columns), may expand nodes
ctrl_n     : search next occurence on exposed rows
ctrl_p     : search previous occurence on exposed rows
N          : search next occurence on any row. may expand more nodes
F6         : popup window for value
F7         : popup window for leaf & root node stats
"""
defaultTableBottomText = "F1:help p:Pivot c:ColOrd v:Views"
if VERSION < v"0.4.0-dev+1930"
    @lintpragma( "DataFrame is a container type" )
    @lintpragma( "AbstractDataFrame is a container type" )
else
    @lintpragma( "DataFrames.DataFrame is a container type" )
    @lintpragma( "DataFrames.AbstractDataFrame is a container type" )
end

type TwTableColInfo
    name::Symbol
    displayname::UTF8String
    format::FormatHints
    aggr::Any
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
        f = liftAggrSpecToFunc( c, aggr )
        ret = f( n.subdataframe )
        if typeof( ret ) <: AbstractDataFrame
            ret = ret[1][1] # first col, first row
        end

        n.colvalcache[c] = ret
        return ret
    end
end

type TwTableView
    name::UTF8String
    pivots::Array{Symbol,1}
    sortorder::Array{ (@compat Tuple{Symbol,Symbol}), 1 } # [ (:col1, :asc ), (:col2, :desc), ... ]
    columns::Array{ Symbol, 1 }
    initdepth::Int
end

# convenient functions to construct views
function TwTableView( df::AbstractDataFrame, name::UTF8String;
    pivots = Symbol[], initdepth=1,
    colorder = Any[ "*" ],
    hidecols = Any[], sortorder = Any[] )

    # construct visible columns in the right order
    function move_columns( targetarray::Array{ Symbol,1 }, sourcearray::Array, remaincols::Array{Symbol,1} )
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

    if eltype( sortorder ) == Symbol
        actualsortorder = (@compat Tuple{Symbol,Symbol})[ (s,:asc) for s in sortorder ]
    elseif eltype( sortorder ) == @compat Tuple{Symbol,Symbol}
        actualsortorder = sortorder
    else
        error( "sortorder eltype expects Symbol, or Tuple{Symbol,Symbol}: " * string( eltype( sortorder ) ) )
    end

    TwTableView( utf8(name), pivots, actualsortorder, finalcolorder, initdepth )
end

# this is the widget data. all subnodes hold a weakref back to this to
# facilitate aggregation, ordering and output
type TwDfTableData
    rootnode::TwDfTableNode
    pivots::Array{ Symbol, 1 }
    sortorder::Array{ (@compat Tuple{Symbol,Symbol}), 1 } # [ (:col1, :asc ), (:col2, :desc), ... ]
    datalist::Array{Any, 1} # (tuple{symbol}, 0) -> node, (tuple{symbol},#) -> row within that sub-df
    datalistlen::Int
    datatreewidth::Int
    headerlines::Int # how many lines does the header occupy, usually just 1
    currentTop::Int
    currentLine::Int
    currentCol::Int
    currentLeft::Int # left most on-screen column
    currentRight::Int # right most on-screen column
    colInfo::Array{ TwTableColInfo, 1 } # only the visible ones, maybe off-screen
    allcolInfo::Dict{ Symbol, TwTableColInfo } # including invisible ones
    bottomText::UTF8String
    helpText::UTF8String
    initdepth::Int
    views::Array{ TwTableView, 1 }
    calcpivots::Dict{ Symbol, CalcPivot }
    searchText::UTF8String
    # calculated dimension
    TwDfTableData() = new( TwDfTableNode(),
        Symbol[], Tuple{Symbol,Symbol}[], Any[], 0, 10, 1, 1, 1, 1, 1, 1, TwTableColInfo[],
        Dict{Symbol,TwTableColInfo}(), "", defaultTableHelpText, 1, TwTableView[], Dict{Symbol,CalcPivot}(),utf8("") )
end

#TODO: allow Regex in formatHints and aggrHints
function newTwDfTable( scr::TwObj, df::DataFrame;
        height::Real=1.0, width::Real=1.0, posy::Any=:center, posx::Any=:center,
        pivots = Symbol[],
        initdepth = 1,
        colorder = Any[ "*" ], # mix of symbol, regex, and "*" (the rest), "*" can be in the middle
        hidecols = Any[], # anything here trumps colorder, Symbol, or Regex
        sortorder = Tuple{Symbol,Symbol}[],
        title = "DataFrame",
        formatHints = Dict{Any,FormatHints}(), # Symbol/Type -> FormatHints
        aggrHints = Dict{Any,Any}(), # Symbol/Type -> string/symbol/expr/function
        widthHints = Dict{Symbol,Int}(),
        headerHints = Dict{Symbol,UTF8String}(),
        bottomText = defaultTableBottomText,
        views = Dict{Symbol,Any}[],
        calcpivots = Dict{Symbol,CalcPivot}() )
    obj = TwObj( TwDfTableData(), Val{:DfTable} )
    obj.value = df
    obj.title = title
    obj.box = true
    obj.borderSizeV= 1
    obj.borderSizeH= 2
    obj.data.rootnode.subdataframe = df
    obj.data.rootnode.context = WeakRef( obj.data )

    mainV = TwTableView( df, utf8( "#Main"), pivots = pivots,
        initdepth=initdepth, sortorder=sortorder, colorder=colorder, hidecols=hidecols )

    obj.data.pivots = mainV.pivots
    obj.data.initdepth = mainV.initdepth
    obj.data.sortorder = mainV.sortorder
    obj.data.calcpivots = calcpivots
    finalcolorder = mainV.columns

    push!( obj.data.views, mainV )
    for (i,d) in enumerate( views )
        if isempty( d )
            error( "nothing in view #" * string( i ) )
        end
        vname = get( d, :name, string( "v#" * string( i ) ) )
        vpivots = get( d, :pivots, pivots )
        vinitdepth = get( d, :initdepth, initdepth )
        vcolorder = get( d, :colorder, colorder )
        vhidecols = get( d, :hidecols, hidecols )
        vsortorder = get( d, :sortorder, sortorder )
        v = TwTableView( df, utf8( vname ), pivots = vpivots, initdepth = vinitdepth,
            sortorder=vsortorder, colorder = vcolorder, hidecols = vhidecols )
        push!( obj.data.views, v )
    end

    # construct colInfo for each col in finalcolorder
    allcols = names( df )
    for c in allcols

        if haskey( calcpivots, c )
            error( "calcpivots interfere with an existing column " * string( c ) )
        end

        t = eltype( df[ c ] )

        hdr = get( headerHints, c, string( c ) )
        fmt = get( formatHints, c,
                get( formatHints, t, deepcopy( FormatHints( t ) ) ) )
        if haskey( widthHints, c )
            fmt.width = widthHints[c]
        end
        agr = get( aggrHints, c,
                get( aggrHints, t, defaultAggr( t ) ) )
        ci = TwTableColInfo( c, hdr, fmt, agr )
        obj.data.allcolInfo[c] = ci
    end

    for c in finalcolorder
        ci = obj.data.allcolInfo[c]
        push!( obj.data.colInfo, ci )
    end

    expandnode( obj.data.rootnode, initdepth )
    ordernode( obj.data.rootnode )
    builddatalist( obj.data )

    updateTableDimensions( obj )
    obj.data.bottomText = bottomText
    link_parent_child( scr, obj, height, width, posy, posx )
    obj
end

function expandnode( n::TwDfTableNode, depth::Int=1 )
    if n.isOpen # nothing to do
        if depth > 1
            for r in n.children
                expandnode( r, depth-1 )
            end
        end
        return
    end
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    if length( npivots ) < length( pivots ) # populate children nodes
        if isempty( n.children )
            nextpivots = deepcopy( npivots )
            nextpivot = pivots[ length( npivots ) + 1 ]
            push!( nextpivots, nextpivot )

            if haskey( n.context.value.calcpivots, nextpivot )
                calcpvt = n.context.value.calcpivots[ nextpivot ]
                pvtspec = calcpvt.spec
                # if we have already pivoted :a, then including it
                # again in *by* would not do anything.
                pvtby   = setdiff( calcpvt.by, npivots )
                f = liftCalcPivotToFunc( pvtspec, pvtby )
                if isempty( pvtby )
                    colvalues = f( n.subdataframe )
                    # Note that setindex! doesn't work for subdataframe
                    # And we most certainly don't want to mutate the original
                    # dataframe (if the node n here is the rootnode)
                    # some sort of composit data frame is needed to
                    # avoid inefficient copying (or is it that bad?)
                    ns = names( n.subdataframe )
                    localdf = DataFrame( [ n.subdataframe[i] for i in 1:length(ns)], ns )
                    localdf[ nextpivot ] = colvalues
                    gd = DataFrames.groupby( localdf, nextpivots )
                else
                    # figure out the aggregation dependency
                    # the lift function just now ensures we have this cache.
                    aggrs = CalcPivotAggrDepCache[ (pvtspec, pvtby) ]
                    kwargs = Any[]
                    for a in aggrs
                        push!( kwargs, ( a, n.context.value.allcolInfo[ a ].aggr ) )
                    end
                    # the lifted function expects us to provide
                    # the aggregation spec on all needed columns,
                    # as keyword arguments
                    df = f( n.subdataframe, nextpivot; kwargs... )
                    gd = DataFrames.groupby( join( n.subdataframe, df, on=pvtby, kind=:left ), nextpivots )
                end
            else
                gd = DataFrames.groupby( n.subdataframe, nextpivots )
            end
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
        if depth > 1
            for r in n.children
                expandnode( r, depth-1 )
            end
        end
    end
    n.isOpen = true
end

# order the children, or if the terminal node, order the subdataframe
# also order opened children (recursive)
function ordernode( n::TwDfTableNode )
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    sortorder = n.context.value.sortorder
    if length( npivots ) < length( pivots ) # populate children nodes
        if length( sortorder ) > 0
            sort!( n.children, lt = (x,y) -> begin
                for sc in sortorder
                    if isna( x[sc[1]] )
                        if !isna( y[sc[1]] )
                            return false
                        else
                            continue
                        end
                    elseif isna( y[sc[1]] )
                        return true
                    end
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
        else
            sort!( n.children, lt = (x,y) -> x.pivotvals[end] < y.pivotvals[end] )
        end
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
                cols=Symbol[x[1] for x in sortorder],
                rev=Bool[x[2]==:desc for x in sortorder ] )
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
    o.data.datalistlen = length( o.data.datalist )
    o.data.headerlines = maximum( map( x->length( split( x.displayname, "\n" ) ), o.data.colInfo ) )
    # reminder: (name, stack, exphints, skiplines, node )
    o.data.datatreewidth = maximum( map( d -> 2*(length(d[2])+1) + length(d[1])+1,
        o.data.datalist ) )
end

function draw( o::TwObj{TwDfTableData} )
    updateTableDimensions( o )
    viewContentHeight = o.height - 2 * o.borderSizeV - o.data.headerlines
    viewContentWidth  = o.width - 2 * o.borderSizeH

    box( o.window, 0,0 )
    if !isempty( o.title )
        titlestr = o.title
        mvwprintw( o.window, 0, (@compat round(Int, ( o.width - length(titlestr) )/2 )), "%s", titlestr )
    end
    if o.data.datalistlen <= viewContentHeight
        msg = "ALL"
    else
        msg = @sprintf( "%d/%d %5.1f%%", o.data.currentLine, o.data.datalistlen,
            o.data.currentLine / o.data.datalistlen * 100 )
    end
    mvwprintw( o.window, 0, o.width - length(msg)-3, "%s", msg )
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

        islastcol = ( startx+width+6 > viewContentWidth ) || col == length( o.data.colInfo )
        if islastcol
            width = min( width, viewContentWidth-startx+2 )
        end
        o.data.currentRight = lastcol = col
        lastwidth = width

        if o.data.currentCol == col
            wattron( o.window, A_REVERSE )
        end
        for (i,line) in enumerate( lines )
            s = ensure_length( line, width )
            if i == nlines
                wattron( o.window, A_UNDERLINE )
            end
            mvwprintw( o.window, i+o.data.headerlines-nlines, startx, "%s", s )
            if i == nlines
                wattroff( o.window, A_UNDERLINE )
            end
        end
        if o.data.currentCol == col
            wattroff( o.window, A_REVERSE )
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
            wattron( o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30 ) )
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
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( @compat Char( 0x25b8 ) ) ) # right-pointing small triangle
        elseif o.data.datalist[r][3] == :open
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, 2*stacklen+2, "%s", string( @compat Char( 0x25be ) ) ) # down-pointing small triangle
        end

        if r == o.data.currentLine
            wattroff( o.window, A_BOLD | COLOR_PAIR(o.hasFocus ? 15 : 30 ) )
        end
        mvwaddch( o.window, o.data.headerlines+1+r-o.data.currentTop, o.data.datatreewidth, get_acs_val( 'x' ) )

        # other columns
        # get the node or DataFrameRow first
        node = o.data.datalist[r][5]
        isnode = (o.data.datalist[r][3] != :single)
        startx = 1+o.data.datatreewidth
        underline =  r < o.data.datalistlen && length( o.data.datalist[r+1][2] ) < stacklen
        for col = o.data.currentLeft:lastcol
            cn = o.data.colInfo[ col ].name
            if isnode
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
            else
                str = applyformat( v, o.data.colInfo[col].format )
                str = ensure_length( str, width )
            end
            flags = underline ? A_UNDERLINE : 0
            if col == o.data.currentCol && r == o.data.currentLine
                flags |= A_BOLD
                if isred
                    flags |= COLOR_PAIR(o.hasFocus ? 9 : 31)
                else
                    flags |= COLOR_PAIR(o.hasFocus ? 15 : 30 )
                end
            elseif isnode
                flags |= A_BOLD
                if  mod( length( o.data.datalist[r][2] ), 2 ) == 0
                    if isred
                        flags |= COLOR_PAIR(1)
                    else
                        flags |= COLOR_PAIR(7)
                    end
                else
                    if isred
                        flags |= COLOR_PAIR(29)
                    else
                        flags |= COLOR_PAIR(13)
                    end
                end
            else
                if isred
                    flags |= COLOR_PAIR(1)
                else
                    flags |= COLOR_PAIR(7)
                end
            end
            wattron( o.window, flags )
            mvwprintw( o.window, o.data.headerlines + 1+r-o.data.currentTop, startx, "%s", str )
            wattroff( o.window, flags )
            if col != lastcol
                mvwaddch( o.window, o.data.headerlines + 1+ r-o.data.currentTop, startx+width, get_acs_val( 'x' ) )
            end
            startx += width + 1
        end
    end
    bottomtext = o.data.bottomText
    pivottext = ""
    if !isempty( o.data.pivots )
        pivottext = "▾"*join( o.data.pivots, "▾" )
    end
    if length( bottomtext ) + length( pivottext ) > o.width-4
        if length( pivottext ) < o.width - 12 # just shorten helptext
            bottomtext = ensure_length( bottomtext, o.width-4-length(pivottext ) )
        else
            bottomtext = ensure_length( bottomtext, 8 )
            pivottext = ensure_length( pivottext, o.width-12 )
        end
    end
    if length( bottomtext ) != 0
        mvwprintw( o.window, o.height-1, 3, "%s", bottomtext )
    end
    if length( pivottext ) != 0
        mvwprintw( o.window, o.height-1, o.width - length( pivottext ) - 1, "%s", pivottext )
    end
end

function inject( o::TwObj{TwDfTableData}, token )
    dorefresh = false
    retcode = :got_it # default behavior is that we know what to do with it
    viewContentHeight = o.height - 2 * o.borderSizeV - o.data.headerlines
    viewContentWidth = o.width - 2* o.borderSizeH - o.data.datatreewidth
    widths = map( x->x.format.width, o.data.colInfo )

    update_tree_data = ()->begin
        builddatalist( o.data )
    end

    checkTop = () -> begin
        o.data.datalistlen = length( o.data.datalist )
        if o.data.currentLine > o.data.datalistlen
            o.data.currentLine = o.data.datalistlen
        end
        if o.data.currentTop < 1
            o.data.currentTop = 1
        end
        if o.data.currentTop > o.data.datalistlen - viewContentHeight + 1
            o.data.currentTop = max(1,o.data.datalistlen - viewContentHeight + 1)
        end
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        end
        if o.data.currentLine - o.data.currentTop > viewContentHeight-1
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

    function searchNext( step::Int, trivialstop::Bool )
        local st = o.data.currentLine
        o.data.searchText = lowercase(o.data.searchText)
        i = trivialstop ? st : ( mod( st-1+step, o.data.datalistlen ) + 1 )
        while true
            node = o.data.datalist[i][5]
            isnode = (o.data.datalist[i][3] != :single)
            # only visible columns and exposed rows are search
            for col in 1:length( o.data.colInfo )
                cn = o.data.colInfo[ col ].name
                if isnode
                    v = node[ cn ]
                else
                    v = node.subdataframesorted[ cn ][ o.data.datalist[i][2][end] ]
                end
                if !( typeof( v ) <: AbstractString )
                    continue
                end

                if contains( lowercase( v ), o.data.searchText )
                    o.data.currentLine = i
                    o.data.currentCol = col
                    checkTop()
                    checkLeft()
                    return i
                end
            end
            i = mod( i-1+step, o.data.datalistlen ) + 1
            if i == st
                beep()
                return 0
            end
        end
    end

    # deep search always go forward
    function searchNextDeep( trivialstop::Bool )
        local st = o.data.currentLine
        local stp = 1

        o.data.searchText = lowercase(o.data.searchText)
        i = trivialstop ? st : ( mod( st-1+stp, o.data.datalistlen ) + 1 )
        ncols = length( o.data.colInfo )
        function checknode( nd::TwDfTableNode, substack::Array{Int,1} )
            function searchdfstring( df::AbstractDataFrame )
                for j in 1:nrow( df )
                    for col in 1:ncols
                        cn = o.data.colInfo[ col ].name
                        v = df[cn][j]
                        if !(typeof(v)<:AbstractString)
                            continue
                        end
                        if contains( lowercase( v ), o.data.searchText )
                            o.data.currentCol = col
                            return j
                        end
                    end
                end
                return 0
            end
            if searchdfstring( nd.subdataframe ) != 0
                if !nd.isOpen
                    expandnode( nd )
                    ordernode( nd )
                end
                if !isempty( nd.children )
                    substacktmp = copy( substack )
                    push!( substacktmp, 0 )
                    for (k,c) in enumerate( nd.children )
                        substacktmp[end] = k
                        ret = checknode( c, substacktmp )
                        if ret != nothing
                            return ret
                        end
                    end
                else
                    therow = searchdfstring( nd.subdataframesorted )
                    substacktmp = copy( substack )
                    push!( substacktmp, therow )
                    #log( "found on " * string( substacktmp ) )
                    return substacktmp
                end
            end
            return nothing
        end
        while true
            node = o.data.datalist[i][5]
            isnode = (o.data.datalist[i][3] != :single)
            if isnode && !node.isOpen
                foundstack = checknode( node, o.data.datalist[i][2] )
                if foundstack != nothing
                    builddatalist( o.data )
                    o.data.currentLine = searchsortedfirst( o.data.datalist, Any[ nothing, foundstack ], by=y->y[2], lt=(s1,s2)->begin
                        #log( "comparing " * string(s1) * " with " * string(s2) )
                        for j in 1:min( length(s1), length(s2) )
                            if s1[j] == s2[j]
                                continue
                            end
                            #log( "Pivot level " * string( j ) * " index is different" )
                            return s1[j] < s2[j]
                        end
                        #log( "All common indices are equal. Pivot lengths are compared" )
                        return length(s1) < length(s2)
                    end )
                    checkTop()
                    checkLeft()
                    return o.data.currentLine
                end
            end
            if !isnode
                for col in 1:ncols
                    cn = o.data.colInfo[ col ].name
                    v = node.subdataframesorted[ cn ][ o.data.datalist[i][2][end] ]
                    if !( typeof( v ) <: AbstractString )
                        continue
                    end

                    if contains( lowercase( v ), o.data.searchText )
                        o.data.currentLine = i
                        o.data.currentCol = col
                        checkTop()
                        checkLeft()
                        return i
                    end
                end
            end
            i = mod( i-1+stp, o.data.datalistlen ) + 1
            if i == st
                beep()
                return 0
            end
        end
    end

    # reminder: (name, stack, exphints, skiplines, node )
    if token == :esc
        retcode = :exit_nothing
    elseif ( token == " " || token == Symbol( "return" ) || token == :enter ) && o.data.datalist[ o.data.currentLine ][3] != :single
        expandhint = o.data.datalist[ o.data.currentLine ][3]
        node = o.data.datalist[ o.data.currentLine][5]
        if node.isOpen
            node.isOpen = false
        else
            expandnode( node )
            ordernode( node )
        end
        update_tree_data()
        checkTop()
        dorefresh = true
    elseif token == "+"
        somethingchanged=false
        for r in 1:length( o.data.datalist )
            if o.data.datalist[r][3] == :close
                node = o.data.datalist[r][5]
                expandnode( node )
                ordernode( node )
                somethingchanged=true
            end
        end
        if somethingchanged
            update_tree_data()
            checkTop()
            dorefresh = true
        else
            beep()
        end
    elseif token == "-"
        somethingchanged=false
        for r in 1:length( o.data.datalist )
            if o.data.datalist[r][3] == :open
                node = o.data.datalist[r][5]
                if !isempty( node.children )
                    if all( x->!x.isOpen, node.children )
                        node.isOpen = false
                        somethingchanged=true
                    end
                else
                    node.isOpen = false
                    somethingchanged=true
                end
            end
        end
        if somethingchanged
            update_tree_data()
            checkTop()
            dorefresh = true
        else
            beep()
        end
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
            widthrng = searchsorted( revcumwidths, viewContentWidth )
            o.data.currentLeft = o.data.currentCol = max( 1, o.data.currentLeft - widthrng.start + 1 )
            checkLeft()
            dorefresh=true
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
            widthrng = searchsorted( cumwidths, viewContentWidth )
            o.data.currentRight = o.data.currentCol = min( o.data.currentRight + widthrng.stop, length( o.data.colInfo ) )
            checkLeft()
            dorefresh=true
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
    elseif token == :KEY_MOUSE
        (mstate,x,y, bs ) = getmouse()
        if mstate == :scroll_up
            dorefresh = movevertical( -(@compat round(Int, viewContentHeight/10 )) )
        elseif mstate == :scroll_down
            dorefresh = movevertical( (@compat round(Int, viewContentHeight/10 )) )
        elseif mstate == :button1_pressed
            rely, relx = screen_to_relative( o.window, y, x )
            if 1<=relx<o.width-1 && o.data.headerlines<rely<o.height-1
                o.data.currentLine = min( o.data.datalistlen, o.data.currentTop + rely - o.borderSizeH + 1 - o.data.headerlines )
                checkTop()
                dorefresh = true
            end
            if o.data.datatreewidth+1<relx<o.width-1 && o.data.headerlines<=rely<o.height-1
                cumwidths = cumsum( map( _->_+1, widths[o.data.currentLeft:end] ) ) # with boundary
                widthrng = searchsorted( cumwidths, relx - o.data.datatreewidth - 1)
                o.data.currentCol = min( length( o.data.colInfo ), o.data.currentLeft + widthrng.start - 1 )
                checkLeft()
                dorefresh = true
            end
            if !dorefresh
                retcode = :pass
            end
        end
    elseif in( token, Any[ Symbol("end") ] )
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
        if width < viewContentWidth-1
            width +=1
            o.data.colInfo[ o.data.currentCol ].format.width = width
            dorefresh = true
        else
            beep()
        end
    elseif token == :ctrl_down
        curr = o.data.currentLine
        stck = o.data.datalist[curr][2]
        if isempty( stck )
            beep()
        else
            if o.data.datalist[curr][3] == :single
                tmpstack = copy( stck )
                pop!( tmpstack )
            else
                tmpstack = stck
            end
            for r in curr+1:length(o.data.datalist )
                rstack = o.data.datalist[r][2]
                if o.data.datalist[r][3] != :single && ( length(rstack) <= length( tmpstack) || rstack[ 1:length( tmpstack ) ] == tmpstack )
                    if r != curr
                        o.data.currentLine = r
                        checkTop()
                        dorefresh = true
                    end
                    break
                end
            end
        end
    elseif token == :ctrl_up
        curr = o.data.currentLine
        stck = o.data.datalist[curr][2]
        if isempty( stck )
            beep()
        else
            tmpstack = copy( stck )
            pop!( tmpstack )
            for r in curr-1:-1:1
                rstack = o.data.datalist[r][2]
                if o.data.datalist[r][3] != :single && length(rstack) <= length( tmpstack)
                    if r != curr
                        o.data.currentLine = r
                        checkTop()
                        dorefresh = true
                    end
                    break
                end
            end
        end
    elseif token == "p"
        allcols = map(_->utf8(string(_)), names( o.data.rootnode.subdataframe ) )
        append!( allcols, map( _->utf8(string(_)), collect( keys( o.data.calcpivots ) ) ) )
        pvts = map( _->utf8(string(_)), o.data.pivots )
        helper = newTwMultiSelect( o.screen.value, allcols, selected = pvts, title="Pivot order", orderable=true, substrsearch=true )
        newpivots = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if newpivots != nothing && newpivots != pvts
            o.data.pivots = Symbol[ Symbol( _ ) for _ in newpivots ]
            o.data.rootnode.children = Any[]
            o.data.rootnode.isOpen = false
            expandnode( o.data.rootnode, o.data.initdepth )
            ordernode( o.data.rootnode )
            update_tree_data()
            o.data.currentLine = 1
            checkTop()
        end
        dorefresh = true
    elseif token == "c"
        allcols = map(_->utf8(string(_)), names( o.data.rootnode.subdataframe ) )
        visiblecols = map( _->utf8(string(_.name)), o.data.colInfo )
        helper = newTwMultiSelect( o.screen.value, allcols, selected = visiblecols, title="Visible columns & their order", orderable=true, substrsearch=true )
        newcols = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if newcols != nothing && newcols != visiblecols
            o.data.colInfo = TwTableColInfo[]
            for c in newcols
                push!( o.data.colInfo, o.data.allcolInfo[ Symbol( c ) ] )
            end
        end
        dorefresh = true
    elseif token == "v"
        allviews = map( _->_.name, o.data.views )
        helper = newTwPopup( o.screen.value, allviews, substrsearch=true, title = "Views" )
        vname = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if vname != nothing
            idx = findfirst( _->_.name == vname, o.data.views )
            v = o.data.views[idx]
            o.data.colInfo = TwTableColInfo[]
            o.data.pivots = v.pivots
            o.data.sortorder = v.sortorder
            o.data.initdepth = v.initdepth
            for c in v.columns
                push!( o.data.colInfo, o.data.allcolInfo[ Symbol( c ) ] )
            end
            o.data.rootnode.children = Any[]
            o.data.rootnode.isOpen = false
            expandnode( o.data.rootnode, o.data.initdepth )
            ordernode( o.data.rootnode )
            update_tree_data()
            o.data.currentLine = 1
            checkTop()
            dorefresh=true
        end
    elseif token == "/"
        helper = newTwEntry( o.screen.value, UTF8String; width=30, posy=:center, posx=:center, title = "Search: " )
        helper.data.inputText = o.data.searchText
        s = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if s != nothing
            if s != "" && o.data.searchText != s
                o.data.searchText = s
                searchNext( 1, true )
            end
        end
        dorefresh = true
    elseif token == "?"
        helper = newTwEntry( o.screen.value, UTF8String; width=30, posy=:center, posx=:center, title = "Search: " )
        helper.data.inputText = o.data.searchText
        s = activateTwObj( helper )
        unregisterTwObj( o.screen.value, helper )
        if s != nothing
            o.data.searchText = s
            searchNextDeep( true )
        end
        dorefresh = true
    elseif token == :ctrl_n
        searchNext( 1, false )
        dorefresh = true
    elseif token == :ctrl_p
        searchNext( -1, false )
        dorefresh = true
    elseif token == "N"
        searchNextDeep( false )
        dorefresh = true
    elseif token == :F6
        colsym = o.data.colInfo[ o.data.currentCol ].name
        node = o.data.datalist[o.data.currentLine][5]
        isnode = (o.data.datalist[o.data.currentLine][3] != :single)
        if isnode
            v = node[ colsym ]
        else
            v = node.subdataframesorted[ colsym ][ o.data.datalist[o.data.currentLine][2][end] ]
        end
        if typeof( v ) != NAtype && !in( v, [ nothing, Void, Any ] )
            tshow( v; title = string( colsym ), posx=:center, posy=:center )
            dorefresh = true
        end
    elseif token == :F7
        colsym = o.data.colInfo[ o.data.currentCol ].name
        node = o.data.datalist[o.data.currentLine][5]
        out = IOBuffer()
        describe( out, node.subdataframe[ colsym ] )

        if node != o.data.rootnode
            println( out, "\nRoot table stats" )
            describe( out, o.data.rootnode.subdataframe[ colsym ] )
        end
        tshow( takebuf_string( out ); title = string( colsym )  * " stats", posx=:center,posy=:center)
        dorefresh = true
    else
        retcode = :pass # I don't know what to do with it
    end

    if dorefresh
        refresh(o)
    end

    return retcode
end

helptext( o::TwObj{TwDfTableData} ) = o.data.helpText
