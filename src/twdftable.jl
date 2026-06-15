defaultTableBottomText = "F1:help p:Pivot c:ColOrd v:Views  F2:Describe  Ctrl-Y:Export"

mutable struct TwTableColInfo
    name::Symbol
    displayname::String
    format::FormatHints
    aggr::Any
end

mutable struct TwDfTableNode
    parent::WeakRef
    context::WeakRef
    pivotcols::Array{Symbol,1}
    pivotvals::Tuple
    isOpen::Bool
    children::Array{Any,1} # only root node can have empty children
    subdataframe::Any
    subdataframesorted::Any
    colvalcache::Dict{Symbol,Any} # order indep aggregated values
    function TwDfTableNode()
        new(
            WeakRef(),
            WeakRef(),
            Symbol[],
            (),
            false,
            Any[],
            nothing,
            nothing,
            Dict{Symbol,Any}(),
        )
    end
    function TwDfTableNode(p::TwDfTableNode)
        x = TwDfTableNode()
        x.parent = WeakRef(p)
        x.context = p.context
        x
    end
end

function getindex(n::TwDfTableNode, c::Symbol)
    if haskey(n.colvalcache, c)
        return n.colvalcache[c]
    else
        context = n.context.value
        aggr = context.allcolInfo[c].aggr
        f = liftAggrSpecToFunc(c, aggr)
        ret = Base.invokelatest(f, n.subdataframe)
        if isa(ret, AbstractDataFrame)
            ret = ret[1, 1] # first col, first row
        end

        n.colvalcache[c] = ret
        return ret
    end
end

mutable struct TwTableView
    name::String
    pivots::Array{Symbol,1}
    sortorder::Array{Tuple{Symbol,Symbol},1} # [ (:col1, :asc ), (:col2, :desc), ... ]
    columns::Array{Symbol,1}
    initdepth::Int
end

# convenient functions to construct views
function TwTableView(
    df::AbstractDataFrame,
    name::String;
    pivots = Symbol[],
    initdepth = 1,
    colorder = Any["*"],
    hidecols = Any[],
    sortorder = Any[],
)

    # construct visible columns in the right order
    function move_columns(
        targetarray::Array{Symbol,1},
        sourcearray::Array,
        remaincols::Array{Symbol,1},
    )
        local i = 1
        local n = length(sourcearray)
        while !isempty(remaincols) && i <= n
            local s = sourcearray[i]
            if s == "*"
                error("illegal extra *")
            elseif isa(s, Regex)
                j = 1
                while j <= length(remaincols)
                    if match(s, string(remaincols[j])) !== nothing
                        push!(targetarray, remaincols[j])
                        deleteat!(remaincols, j)
                        continue
                    end
                    j += 1
                end
            elseif isa(s, Symbol)
                if !in(s, remaincols)
                    error(
                        "Column " *
                        string(s) *
                        " not in " *
                        string(remaincols) *
                        " src:" *
                        string(sourcearray),
                    )
                end
                push!(targetarray, s)
                local idx = findfirst(isequal(s), remaincols)
                deleteat!(remaincols, idx)
            else
                error("illegal " * string(s) * " found")
            end

            i += 1
        end
    end

    remaincols = Symbol.(names(df))
    if in("*", colorder)
        colspreast = Symbol[]
        colspostast = Symbol[]
        local idx = findfirst(isequal("*"), colorder)
        move_columns(colspreast, colorder[1:(idx-1)], remaincols)
        finalcolorder = colspreast
        move_columns(colspostast, colorder[(idx+1):length(colorder)], remaincols)
        append!(finalcolorder, remaincols)
        append!(finalcolorder, colspostast)
    else
        finalcolorder = Symbol[]
        move_columns(finalcolorder, colorder, remaincols)
    end

    # remove anything in hidecols
    removed = Symbol[]
    move_columns(removed, hidecols, finalcolorder)

    if eltype(sortorder) == Symbol
        actualsortorder = Tuple{Symbol,Symbol}[(s, :asc) for s in sortorder]
    elseif eltype(sortorder) == Tuple{Symbol,Symbol}
        actualsortorder = sortorder
    else
        error(
            "sortorder eltype expects Symbol, or Tuple{Symbol,Symbol}: " *
            string(eltype(sortorder)),
        )
    end

    TwTableView(name, pivots, actualsortorder, finalcolorder, initdepth)
end

# this is the widget data. all subnodes hold a weakref back to this to
# facilitate aggregation, ordering and output
mutable struct TwDfTableData
    rootnode::TwDfTableNode
    pivots::Array{Symbol,1}
    sortorder::Array{Tuple{Symbol,Symbol},1} # [ (:col1, :asc ), (:col2, :desc), ... ]
    datalist::Array{Any,1} # (tuple{symbol}, 0) -> node, (tuple{symbol},#) -> row within that sub-df
    datalistlen::Int
    datatreewidth::Int
    headerlines::Int # how many lines does the header occupy, usually just 1
    currentTop::Int
    currentLine::Int
    currentCol::Int
    currentLeft::Int # left most on-screen column
    currentRight::Int # right most on-screen column
    colInfo::Array{TwTableColInfo,1} # only the visible ones, maybe off-screen
    allcolInfo::Dict{Symbol,TwTableColInfo} # including invisible ones
    bottomText::String
    initdepth::Int
    views::Array{TwTableView,1}
    calcpivots::Dict{Symbol,CalcPivot}
    searchText::String
    selection_text::Observable{String}
    showRoot::Bool   # when false, the root summary row is hidden (flat-list display)
    # calculated dimension
    TwDfTableData() = new(
        TwDfTableNode(),
        Symbol[],
        Tuple{Symbol,Symbol}[],
        Any[],
        0,
        10,
        1,
        1,
        1,
        1,
        1,
        1,
        TwTableColInfo[],
        Dict{Symbol,TwTableColInfo}(),
        "",
        1,
        TwTableView[],
        Dict{Symbol,CalcPivot}(),
        "",
        Observable(""),
        true,
    )
end

#TODO: allow Regex in formatHints and aggrHints
function newTwDfTable(
    scr::TwObj,
    df::DataFrame;
    height::Real = 1.0,
    width::Real = 1.0,
    posy::Any = :center,
    posx::Any = :center,
    pivots = Symbol[],
    initdepth = 1,
    colorder = Any["*"], # mix of symbol, regex, and "*" (the rest), "*" can be in the middle
    hidecols = Any[], # anything here trumps colorder, Symbol, or Regex
    sortorder = Tuple{Symbol,Symbol}[],
    title = "DataFrame",
    formatHints = Dict{Any,FormatHints}(), # Symbol/Type -> FormatHints
    aggrHints = Dict{Any,Any}(), # Symbol/Type -> string/symbol/expr/function
    widthHints = Dict{Symbol,Int}(),
    headerHints = Dict{Symbol,String}(),
    bottomText = defaultTableBottomText,
    views = Dict{Symbol,Any}[],
    calcpivots = Dict{Symbol,CalcPivot}(),
    showRoot::Bool = true,
)
    obj = TwObj(TwDfTableData(), Val{:DfTable})
    obj.data.showRoot = showRoot
    obj.value = df
    obj.title = title
    obj.box = true
    obj.borderSizeV = 1
    obj.borderSizeH = 2
    obj.data.rootnode.subdataframe = df
    obj.data.rootnode.context = WeakRef(obj.data)

    mainV = TwTableView(
        df,
        "#Main",
        pivots = pivots,
        initdepth = initdepth,
        sortorder = sortorder,
        colorder = colorder,
        hidecols = hidecols,
    )

    obj.data.pivots = mainV.pivots
    obj.data.initdepth = mainV.initdepth
    obj.data.sortorder = mainV.sortorder
    obj.data.calcpivots = calcpivots
    finalcolorder = mainV.columns

    push!(obj.data.views, mainV)
    for (i, d) in enumerate(views)
        if isempty(d)
            error("nothing in view #" * string(i))
        end
        vname = get(d, :name, string("v#" * string(i)))
        vpivots = get(d, :pivots, pivots)
        vinitdepth = get(d, :initdepth, initdepth)
        vcolorder = get(d, :colorder, colorder)
        vhidecols = get(d, :hidecols, hidecols)
        vsortorder = get(d, :sortorder, sortorder)
        v = TwTableView(
            df,
            vname,
            pivots = vpivots,
            initdepth = vinitdepth,
            sortorder = vsortorder,
            colorder = vcolorder,
            hidecols = vhidecols,
        )
        push!(obj.data.views, v)
    end

    # construct colInfo for each col in finalcolorder
    allcols = Symbol.(names(df))
    for c in allcols

        if haskey(calcpivots, c)
            error("calcpivots interfere with an existing column " * string(c))
        end

        t = eltype(df[!, c])

        hdr = get(headerHints, c, string(c))
        fmt = get(formatHints, c, get(formatHints, t, deepcopy(FormatHints(t))))
        if haskey(widthHints, c)
            fmt.width = widthHints[c]
        end
        agr = get(aggrHints, c, get(aggrHints, t, defaultAggr(t)))
        ci = TwTableColInfo(c, hdr, fmt, agr)
        obj.data.allcolInfo[c] = ci
    end

    for c in finalcolorder
        ci = obj.data.allcolInfo[c]
        push!(obj.data.colInfo, ci)
    end

    expandnode(obj.data.rootnode, initdepth)
    ordernode(obj.data.rootnode)
    builddatalist(obj.data)

    updateTableDimensions(obj)
    obj.data.bottomText = bottomText
    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

function expandnode(n::TwDfTableNode, depth::Int = 1)
    if n.isOpen # nothing to do
        if depth > 1
            for r in n.children
                expandnode(r, depth-1)
            end
        end
        return
    end
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    if length(npivots) < length(pivots) # populate children nodes
        if isempty(n.children)
            nextpivots = deepcopy(npivots)
            nextpivot = pivots[length(npivots)+1]
            push!(nextpivots, nextpivot)

            if haskey(n.context.value.calcpivots, nextpivot)
                calcpvt = n.context.value.calcpivots[nextpivot]
                pvtspec = calcpvt.spec
                # if we have already pivoted :a, then including it
                # again in *by* would not do anything.
                pvtby = setdiff(calcpvt.by, npivots)
                f = liftCalcPivotToFunc(pvtspec, pvtby)
                if isempty(pvtby)
                    colvalues = Base.invokelatest(f, n.subdataframe)
                    # Note that setindex! doesn't work for subdataframe
                    # And we most certainly don't want to mutate the original
                    # dataframe (if the node n here is the rootnode)
                    # some sort of composit data frame is needed to
                    # avoid inefficient copying (or is it that bad?)
                    localdf = DataFrame(n.subdataframe)
                    localdf[!, nextpivot] = colvalues
                    gd = DataFrames.groupby(localdf, nextpivots)
                else
                    # figure out the aggregation dependency
                    # the lift function just now ensures we have this cache.
                    aggrs = CalcPivotAggrDepCache[(pvtspec, pvtby)]
                    kwargs = Any[]
                    for a in aggrs
                        push!(kwargs, (a, n.context.value.allcolInfo[a].aggr))
                    end
                    # the lifted function expects us to provide
                    # the aggregation spec on all needed columns,
                    # as keyword arguments
                    df = Base.invokelatest(f, n.subdataframe, nextpivot; kwargs...)
                    gd = DataFrames.groupby(
                        leftjoin(n.subdataframe, df, on = pvtby),
                        nextpivots,
                    )
                end
            else
                gd = DataFrames.groupby(n.subdataframe, nextpivots)
            end
            for g in gd
                valtuple = Tuple(g[1, c] for c in nextpivots)
                r = TwDfTableNode(n)
                r.pivotcols = nextpivots
                r.pivotvals = valtuple
                r.subdataframe = g
                push!(n.children, r)
            end
        end
        if depth > 1
            for r in n.children
                expandnode(r, depth-1)
            end
        end
    end
    n.isOpen = true
end

# order the children, or if the terminal node, order the subdataframe
# also order opened children (recursive)
function ordernode(n::TwDfTableNode)
    pivots = n.context.value.pivots
    npivots = n.pivotcols # this is the node's pivot. length <= length( pivots )
    sortorder = n.context.value.sortorder
    if length(npivots) < length(pivots) # populate children nodes
        if length(sortorder) > 0
            sort!(n.children, lt = (x, y) -> begin
                for sc in sortorder
                    if ismissing(x[sc[1]])
                        if !ismissing(y[sc[1]])
                            return false
                        else
                            continue
                        end
                    elseif ismissing(y[sc[1]])
                        return true
                    end
                    if x[sc[1]] == y[sc[1]]
                        continue
                    end

                    # Use isless, not <: unordered CategoricalValue (produced
                    # by discretize/topnames) throws on <, but isless falls
                    # back to pool order — and discretize's zero-padded rank
                    # prefixes ("1. …", "2. …") keep that order meaningful.
                    if sc[2] == :desc
                        return isless(y[sc[1]], x[sc[1]])
                    else
                        return isless(x[sc[1]], y[sc[1]])
                    end
                end
                return false
            end)
        else
            sort!(n.children, lt = (x, y) -> isless(x.pivotvals[end], y.pivotvals[end]))
        end
        for c in n.children
            if c.isOpen
                ordernode(c)
            end
        end
    else
        if length(sortorder) == 0
            n.subdataframesorted = n.subdataframe
        else
            n.subdataframesorted = sort(
                n.subdataframe,
                Symbol[x[1] for x in sortorder];
                rev = Bool[x[2]==:desc for x in sortorder],
            )
        end
    end
end

function builddatalist(o::TwDfTableData)
    o.datalist = Any[]
    pivots = o.pivots

    function presublist(
        subn::TwDfTableNode,
        substack::Array{Int,1},
        skiplines::Array{Int,1},
        islast::Bool,
    )
        if islast
            newskip = copy(skiplines)
            push!(newskip, length(substack))
            sublist(subn, substack, newskip)
        else
            sublist(subn, substack, skiplines)
        end
    end

    function sublist(n::TwDfTableNode, stack::Array{Int,1}, skiplines::Array{Int,1})
        if isempty(n.pivotvals)
            name = "Root"
        else
            name = string(n.pivotvals[end])
        end

        if o.showRoot || !isempty(stack)
            push!(o.datalist, (name, stack, n.isOpen ? :open : :close, skiplines, n))
        end
        if n.isOpen
            if length(n.pivotcols) < length(pivots)
                len = length(n.children)
                for (i, c) in enumerate(n.children)
                    substack = copy(stack)
                    push!(substack, i)
                    presublist(c, substack, skiplines, i==len)
                end
            else
                for i = 1:size(n.subdataframe, 1)
                    substack = copy(stack)
                    push!(substack, i)
                    push!(o.datalist, (string(i), substack, :single, skiplines, n))
                end
            end
        end
    end

    sublist(o.rootnode, Int[], Int[])
    o.currentLine = min(o.currentLine, length(o.datalist))
end

# In-place DataFrame replacement — updates the displayed data without resetting
# scroll position, column config, or sort settings.
# Intended for live-widget update 
# Precondition: flat (no pivot groups) DataFrame with the same schema as at construction.
function setvalue!(o::TwObj{TwDfTableData}, df::DataFrame)
    o.value = df
    o.data.rootnode.subdataframe = df
    o.data.rootnode.colvalcache  = Dict{Symbol,Any}()
    ordernode(o.data.rootnode)
    builddatalist(o.data)
end

function updateTableDimensions(o::TwObj)
    o.data.datalistlen = length(o.data.datalist)
    o.data.headerlines = maximum(map(x->length(split(x.displayname, "\n")), o.data.colInfo))
    # reminder: (name, stack, exphints, skiplines, node )
    o.data.datatreewidth =
        maximum(map(d -> 2*(length(d[2])+1) + length(d[1]) + 1, o.data.datalist))
end

function draw(o::TwObj{TwDfTableData})
    updateTableDimensions(o)
    viewContentHeight = o.height - 2 * o.borderSizeV - o.data.headerlines
    viewContentWidth = o.width - 2 * o.borderSizeH

    if o.box
        box(o.window, 0, 0)
        if !isempty(o.title)
            titlestr = o.title
            mvwprintw(o.window, 0, round(Int, (o.width - length(titlestr))/2), "%s", titlestr)
        end
        if o.data.datalistlen <= viewContentHeight
            msg = "ALL"
        else
            msg = @sprintf(
                "%d/%d %5.1f%%",
                o.data.currentLine,
                o.data.datalistlen,
                o.data.currentLine / o.data.datalistlen * 100
            )
        end
        mvwprintw(o.window, 0, o.width - length(msg)-3, "%s", msg)
    end
    updateTableDimensions(o)

    # header row(s)
    wattron(o.window, theme(:header))
    startx = 1+o.data.datatreewidth
    lastcol = 1
    lastwidth = 8
    for col = o.data.currentLeft:length(o.data.colInfo)
        if startx > viewContentWidth
            break
        end
        ci = o.data.colInfo[col]
        lines = split(ci.displayname, "\n")
        nlines = length(lines)
        width = ci.format.width

        islastcol = (startx+width+6 > viewContentWidth) || col == length(o.data.colInfo)
        if islastcol
            width = min(width, viewContentWidth-startx+2)
        end
        o.data.currentRight = lastcol = col
        lastwidth = width

        if o.data.currentCol == col
            wattron(o.window, A_REVERSE)
        end
        for (i, line) in enumerate(lines)
            s = ensure_length(line, width)
            if i == nlines
                wattron(o.window, A_UNDERLINE)
            end
            mvwprintw(o.window, i+o.data.headerlines-nlines, startx, "%s", s)
            if i == nlines
                wattroff(o.window, A_UNDERLINE)
            end
        end
        if o.data.currentCol == col
            wattroff(o.window, A_REVERSE)
	    wattron(o.window, theme(:header))
        end
        if !islastcol
            for i = 1:o.data.headerlines
                mvwaddch(o.window, i, startx+width, get_acs_val('x'))
            end
        end
        startx += width + 1
    end
    wattroff(o.window, theme(:header))
    # reminder: (name, stack, exphints, skiplines, node )
    for r = o.data.currentTop:min(o.data.currentTop+viewContentHeight-1, o.data.datalistlen)

        stacklen = length(o.data.datalist[r][2])

        # treecolume is always shown
        s = ensure_length(
            repeat(" ", 2*stacklen + 1) * o.data.datalist[r][1],
            o.data.datatreewidth-2,
        )

        if r == o.data.currentLine
            wattron(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end
        mvwprintw(o.window, o.data.headerlines + 1 + r-o.data.currentTop, 2, "%s", s)
        for i = 1:(stacklen-1)
            if !in(i, o.data.datalist[r][4]) # skiplines
                mvwaddch(
                    o.window,
                    o.data.headerlines + 1 + r-o.data.currentTop,
                    2*i,
                    get_acs_val('x'),
                ) # vertical line
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t') # tee pointing right
            if r == o.data.datalistlen ||  # end of the whole thing
               length(o.data.datalist[r+1][2]) < stacklen || # next one is going back in level
               (
                   length(o.data.datalist[r+1][2]) > stacklen &&
                   in(stacklen, o.data.datalist[r+1][4])
               ) # going deeper in level
                contchar = get_acs_val('m') # LL corner
            end
            mvwaddch(
                o.window,
                o.data.headerlines + 1 + r-o.data.currentTop,
                2*stacklen,
                contchar,
            )
            mvwaddch(
                o.window,
                o.data.headerlines + 1 + r-o.data.currentTop,
                2*stacklen+1,
                get_acs_val('q'),
            ) # horizontal line
        end
        if o.data.datalist[r][3] == :close
            mvwprintw(
                o.window,
                o.data.headerlines + 1 + r-o.data.currentTop,
                2*stacklen+2,
                "%s",
                string(Char(0x25b8)),
            ) # right-pointing small triangle
        elseif o.data.datalist[r][3] == :open
            mvwprintw(
                o.window,
                o.data.headerlines + 1 + r-o.data.currentTop,
                2*stacklen+2,
                "%s",
                string(Char(0x25be)),
            ) # down-pointing small triangle
        end

        if r == o.data.currentLine
            wattroff(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end
        mvwaddch(
            o.window,
            o.data.headerlines+1+r-o.data.currentTop,
            o.data.datatreewidth,
            get_acs_val('x'),
        )

        # other columns
        # get the node or DataFrameRow first
        node = o.data.datalist[r][5]
        isnode = (o.data.datalist[r][3] != :single)
        startx = 1+o.data.datatreewidth
        underline = r < o.data.datalistlen && length(o.data.datalist[r+1][2]) < stacklen
        for col = o.data.currentLeft:lastcol
            cn = o.data.colInfo[col].name
            if isnode
                v = node[cn]
            else
                v = node.subdataframesorted[!, cn][o.data.datalist[r][2][end]]
            end
            width = (col == lastcol ? lastwidth : o.data.colInfo[col].format.width)
            isred = false
            if ismissing(v)
                str = ensure_length("", width)
            elseif isa(v, Real)
                str = applyformat(v, o.data.colInfo[col].format)
                if length(str) > width # all ####
                    str = repeat("#", width)
                elseif length(str) < width
                    str = repeat(" ", width - length(str)) * str
                end
                isred = v < 0
            else
                str = applyformat(v, o.data.colInfo[col].format)
                str = ensure_length(str, width)
            end
            flags = underline ? A_UNDERLINE : 0
            if col == o.data.currentCol && r == o.data.currentLine
                flags |= A_BOLD
                if isred
                    flags |= COLOR_PAIR(o.hasFocus ? 9 : 31)
                else
                    flags |= theme(o.hasFocus ? :selection_focused : :selection_unfocused)
                end
            elseif isnode
                flags |= A_BOLD
                if mod(length(o.data.datalist[r][2]), 2) == 0
                    if isred
                        flags |= theme(:negative)
                    else
                        flags |= COLOR_PAIR(7)
                    end
                else
                    if isred
                        flags |= COLOR_PAIR(29)
                    else
                        flags |= theme(:divider)
                    end
                end
            else
                if isred
                    flags |= theme(:negative)
                else
                    flags |= COLOR_PAIR(7)
                end
            end
            wattron(o.window, flags)
            mvwprintw(
                o.window,
                o.data.headerlines + 1 + r-o.data.currentTop,
                startx,
                "%s",
                str,
            )
            wattroff(o.window, flags)
            if col != lastcol
                mvwaddch(
                    o.window,
                    o.data.headerlines + 1 + r-o.data.currentTop,
                    startx+width,
                    get_acs_val('x'),
                )
            end
            startx += width + 1
        end
    end
    bottomtext = o.data.bottomText
    pivottext = ""
    if !isempty(o.data.pivots)
        pivottext = "▾"*join(o.data.pivots, "▾")
    end
    if length(bottomtext) + length(pivottext) > o.width-4
        if length(pivottext) < o.width - 12 # just shorten helptext
            bottomtext = ensure_length(bottomtext, o.width-4-length(pivottext))
        else
            bottomtext = ensure_length(bottomtext, 8)
            pivottext = ensure_length(pivottext, o.width-12)
        end
    end
    if length(bottomtext) != 0
        mvwprintw(o.window, o.height-1, 3, "%s", bottomtext)
    end
    if length(pivottext) != 0
        mvwprintw(o.window, o.height-1, o.width - length(pivottext) - 1, "%s", pivottext)
    end
end

function _dt_cell_str(node::TwDfTableNode, exphint::Symbol, stack::Array{Int,1}, col::TwTableColInfo)::String
    try
        if exphint == :single
            val = node.subdataframesorted[!, col.name][stack[end]]
            return ismissing(val) ? "" : applyformat(val, col.format)
        else
            val = node[col.name]
            return (val === nothing || ismissing(val)) ? "" : applyformat(val, col.format)
        end
    catch
        return ""
    end
end

function _dt_extract_rows(data::TwDfTableData)
    rows = NamedTuple{(:depth, :is_leaf, :pivot_name, :cells), Tuple{Int,Bool,String,Vector{String}}}[]
    for entry in data.datalist
        (name, stack, exphint, skiplines, node) = entry
        is_leaf = (exphint == :single)
        depth = length(node.pivotcols) + (is_leaf ? 1 : 0)
        cells = String[_dt_cell_str(node, exphint, stack, col) for col in data.colInfo]
        push!(rows, (depth=depth, is_leaf=is_leaf, pivot_name=name, cells=cells))
    end
    rows
end

function _dt_to_csv(data::TwDfTableData; indent::Bool=true)::String
    lines = String[]
    header = join(vcat(["Group"], [c.displayname for c in data.colInfo]), "\t")
    push!(lines, header)
    for row in _dt_extract_rows(data)
        prefix = indent ? ">"^row.depth : ""
        push!(lines, prefix * row.pivot_name * "\t" * join(row.cells, "\t"))
    end
    join(lines, "\n")
end

const _DT_PIVOT_COLORS = ["#2a3a2a", "#3a2a2a", "#2a2a3a", "#3a3a2a"]  # green, red, blue, yellow tints

function _dt_to_html(data::TwDfTableData, title::String)::String
    cols = data.colInfo
    ncols = length(cols)

    # Detect numeric columns for right-alignment
    is_num = Bool[
        all(r -> r.is_leaf ? tryparse(Float64, r.cells[i]) !== nothing || r.cells[i] == "" : true,
            _dt_extract_rows(data))
        for i in 1:ncols
    ]

    rows_data = _dt_extract_rows(data)

    # Build CSS
    pivot_css = join(
        ["tr.depth-$(d) { background-color: $(_DT_PIVOT_COLORS[mod1(d, 4)]); font-weight: bold; }"
         for d in 1:8],
        "\n    "
    )

    col_widths = join(
        ["col.c$(i) { width: $(max(4, cols[i].format.width) * 8)px; }" for i in 1:ncols],
        "\n    "
    )

    css = """
    body { background:#1e1e1e; color:#e0e0e0; font-family:monospace; font-size:13px; margin:12px; }
    h2 { color:#a0c0ff; }
    table { border-collapse:collapse; border-spacing:0; }
    th { background:#1a3a6a; color:#fff; padding:3px 8px; text-align:left; white-space:nowrap; border:1px solid #333; }
    td { padding:2px 8px; white-space:nowrap; border:1px solid #2e2e2e; }
    tr.leaf:nth-child(odd) td { background:#242424; }
    tr.leaf:nth-child(even) td { background:#2c2c2c; }
    $pivot_css
    td.num { text-align:right; }
    $col_widths"""

    # Build header
    header_cells = join(["<th>$(escapeHTML(c.displayname))</th>" for c in cols], "")
    thead = "<thead><tr><th>Group</th>$header_cells</tr></thead>"

    # Build body rows
    tbody_lines = String[]
    leaf_idx = 0
    for row in rows_data
        if row.is_leaf
            leaf_idx += 1
            cls = "leaf"
        else
            cls = "depth-$(row.depth)"
        end
        indent_px = row.depth * 16
        tree_td = "<td style=\"padding-left:$(indent_px)px\">$(escapeHTML(row.pivot_name))</td>"
        data_tds = join([
            "<td class=\"$(is_num[i] ? "num" : "")\">$(escapeHTML(row.cells[i]))</td>"
            for i in 1:ncols
        ], "")
        push!(tbody_lines, "<tr class=\"$cls\">$tree_td$data_tds</tr>")
    end
    tbody = "<tbody>$(join(tbody_lines, "\n"))</tbody>"

    colgroup = "<colgroup><col class=\"c0\">" *
        join(["<col class=\"c$(i)\">" for i in 1:ncols], "") * "</colgroup>"

    title_html = isempty(title) ? "" : "<h2>$(escapeHTML(title))</h2>\n"
    nrows = count(r -> r.is_leaf, rows_data)
    subtitle = "<p style=\"color:#888;font-size:11px\">$(nrows) rows, $(ncols) columns</p>\n"

    """<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>$(escapeHTML(title))</title>
<style>$css</style>
</head><body>
$(title_html)$(subtitle)<table>$colgroup$thead\n$tbody\n</table>
</body></html>"""
end

function escapeHTML(s::AbstractString)::String
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s
end

function _dt_open_browser(path::String)
    try
        if Sys.isapple()
            run(`open $path`, wait = false)
        elseif Sys.iswindows()
            run(`cmd /c start "" $path`, wait = false)
        else
            run(`xdg-open $path`, wait = false)
        end
    catch
        beep()
    end
end

function _dt_export_menu!(o::TwObj{TwDfTableData})
    global rootTwScreen
    options = ["HTML → browser", "CSV → clipboard", "CSV → file", "TSV → clipboard", "Cancel"]
    popup = newTwPopup(
        o.screen.value,
        options;
        posy = :center, posx = :center,
        title = "Export view",
        substrsearch = true,
        maxheight = length(options) + 2,
        maxwidth = 28,
    )
    result = activateTwObj(popup)
    unregisterTwObj(o.screen.value, popup)

    result === nothing && return
    result == "Cancel" && return

    data = o.data
    if result == "HTML → browser"
        html = _dt_to_html(data, o.title)
        tmp = tempname() * ".html"
        try
            write(tmp, html)
            _dt_open_browser(tmp)
        catch
            beep()
        end
    elseif result == "CSV → clipboard"
        csv = _dt_to_csv(data; indent = true)
        _et_clipboard_write(csv)
    elseif result == "CSV → file"
        entry = newTwEntry(
            o.screen.value,
            String;
            title = "Save CSV to:",
            width = 50,
            posy = :center, posx = :center,
        )
        path = activateTwObj(entry)
        unregisterTwObj(o.screen.value, entry)
        if path !== nothing && path != ""
            try
                write(path, _dt_to_csv(data; indent = true))
            catch
                beep()
            end
        end
    elseif result == "TSV → clipboard"
        tsv = _dt_to_csv(data; indent = false)
        _et_clipboard_write(tsv)
    end
    refresh(o)
end

_dft_vph(o::TwObj{TwDfTableData}) = o.height - 2 * o.borderSizeV - o.data.headerlines
_dft_vpw(o::TwObj{TwDfTableData}) = o.width  - 2 * o.borderSizeH - o.data.datatreewidth

function _dft_check_top!(o::TwObj{TwDfTableData})
    vch = _dft_vph(o)
    o.data.datalistlen = length(o.data.datalist)
    if o.data.currentLine > o.data.datalistlen
        o.data.currentLine = o.data.datalistlen
    end
    if o.data.currentTop < 1
        o.data.currentTop = 1
    end
    if o.data.currentTop > o.data.datalistlen - vch + 1
        o.data.currentTop = max(1, o.data.datalistlen - vch + 1)
    end
    if o.data.currentTop > o.data.currentLine
        o.data.currentTop = o.data.currentLine
    end
    if o.data.currentLine - o.data.currentTop > vch - 1
        o.data.currentTop = o.data.currentLine - vch + 1
    end
end

function _dft_check_left!(o::TwObj{TwDfTableData})
    vcw = _dft_vpw(o)
    widths = map(x->x.format.width, o.data.colInfo)
    if o.data.currentLeft < 1
        o.data.currentLeft = 1
    else
        revcumwidths = cumsum(map(x->x+1, reverse(widths)))
        widthrng = searchsorted(revcumwidths, vcw)
        if o.data.currentLeft > length(o.data.colInfo) - widthrng.stop + 1
            o.data.currentLeft = length(o.data.colInfo) - widthrng.stop + 1
        end
    end
    if o.data.currentLeft > o.data.currentCol
        o.data.currentLeft = o.data.currentCol
    else
        revcumwidths = cumsum(map(x->x+1, reverse(widths[o.data.currentLeft:o.data.currentCol])))
        widthrng = searchsorted(revcumwidths, vcw)
        if o.data.currentLeft < o.data.currentCol - widthrng.stop + 1
            o.data.currentLeft = o.data.currentCol - widthrng.stop + 1
        end
    end
end

function _dft_movev!(o::TwObj{TwDfTableData}, n::Int)
    old = o.data.currentLine
    o.data.currentLine = max(1, min(o.data.datalistlen, o.data.currentLine + n))
    if old != o.data.currentLine
        _dft_check_top!(o)
        return true
    else
        beep()
        return false
    end
end

function _dft_moveh!(o::TwObj{TwDfTableData}, n::Int)
    old = o.data.currentCol
    o.data.currentCol = max(1, min(length(o.data.colInfo), o.data.currentCol + n))
    if old != o.data.currentCol
        _dft_check_left!(o)
        return true
    else
        beep()
        return false
    end
end

function _dft_ctrl_left!(o::TwObj{TwDfTableData})
    vcw = _dft_vpw(o)
    widths = map(x->x.format.width, o.data.colInfo)
    if o.data.currentCol != o.data.currentLeft
        o.data.currentCol = o.data.currentLeft
        return true
    elseif o.data.currentLeft == 1
        beep()
        return false
    else
        revcumwidths = cumsum(map(x->x+1, reverse(widths[1:o.data.currentLeft])))
        widthrng = searchsorted(revcumwidths, vcw)
        o.data.currentLeft = o.data.currentCol = max(1, o.data.currentLeft - widthrng.start + 1)
        _dft_check_left!(o)
        return true
    end
end

function _dft_ctrl_right!(o::TwObj{TwDfTableData})
    vcw = _dft_vpw(o)
    widths = map(x->x.format.width, o.data.colInfo)
    if o.data.currentCol != o.data.currentRight
        o.data.currentCol = o.data.currentRight
        return true
    elseif o.data.currentRight == length(o.data.colInfo)
        beep()
        return false
    else
        cumwidths = cumsum(map(x->x+1, reverse(widths[o.data.currentRight:end])))
        widthrng = searchsorted(cumwidths, vcw)
        o.data.currentRight = o.data.currentCol =
            min(o.data.currentRight + widthrng.stop, length(o.data.colInfo))
        _dft_check_left!(o)
        return true
    end
end

function _dft_next_sibling!(o::TwObj{TwDfTableData})
    curr = o.data.currentLine
    stck = o.data.datalist[curr][2]
    if isempty(stck)
        beep(); return false
    end
    tmpstack = copy(stck); pop!(tmpstack)
    for r = (curr+1):length(o.data.datalist)
        rstack = o.data.datalist[r][2]
        if length(rstack) == length(tmpstack)+1 && rstack[1:length(tmpstack)] == tmpstack
            o.data.currentLine = r
            _dft_check_top!(o)
            return true
        end
    end
    beep(); return false
end

function _dft_prev_sibling!(o::TwObj{TwDfTableData})
    curr = o.data.currentLine
    stck = o.data.datalist[curr][2]
    if isempty(stck)
        beep(); return false
    end
    tmpstack = copy(stck); pop!(tmpstack)
    for r = (curr-1):-1:1
        rstack = o.data.datalist[r][2]
        if length(rstack) == length(tmpstack)+1 && rstack[1:length(tmpstack)] == tmpstack
            o.data.currentLine = r
            _dft_check_top!(o)
            return true
        end
    end
    beep(); return false
end

function _dft_expand_all!(o::TwObj{TwDfTableData})
    changed = false
    for r = 1:length(o.data.datalist)
        if o.data.datalist[r][3] == :close
            node = o.data.datalist[r][5]
            expandnode(node); ordernode(node)
            changed = true
        end
    end
    if changed
        builddatalist(o.data); _dft_check_top!(o)
    else
        beep()
    end
end

function _dft_collapse_all!(o::TwObj{TwDfTableData})
    changed = false
    for r = 1:length(o.data.datalist)
        if o.data.datalist[r][3] == :open
            node = o.data.datalist[r][5]
            if !isempty(node.children)
                if all(x->!x.isOpen, node.children)
                    node.isOpen = false; changed = true
                end
            else
                node.isOpen = false; changed = true
            end
        end
    end
    if changed
        builddatalist(o.data); _dft_check_top!(o)
    else
        beep()
    end
end

function _dft_search_next!(o::TwObj{TwDfTableData}, step::Int, trivialstop::Bool)
    local st = o.data.currentLine
    o.data.searchText = lowercase(o.data.searchText)
    i = trivialstop ? st : (mod(st-1+step, o.data.datalistlen) + 1)
    while true
        node  = o.data.datalist[i][5]
        isnode = (o.data.datalist[i][3] != :single)
        for col = 1:length(o.data.colInfo)
            cn = o.data.colInfo[col].name
            v  = isnode ? node[cn] : node.subdataframesorted[!, cn][o.data.datalist[i][2][end]]
            isa(v, AbstractString) || continue
            if occursin(o.data.searchText, lowercase(v))
                o.data.currentLine = i
                o.data.currentCol  = col
                _dft_check_top!(o); _dft_check_left!(o)
                return i
            end
        end
        i = mod(i-1+step, o.data.datalistlen) + 1
        if i == st; beep(); return 0; end
    end
end

function _dft_search_next_deep!(o::TwObj{TwDfTableData}, trivialstop::Bool)
    local st  = o.data.currentLine
    local stp = 1
    o.data.searchText = lowercase(o.data.searchText)
    i = trivialstop ? st : (mod(st-1+stp, o.data.datalistlen) + 1)
    ncols = length(o.data.colInfo)
    function checknode(nd::TwDfTableNode, substack::Array{Int,1})
        function searchdfstring(df::AbstractDataFrame)
            for j = 1:nrow(df)
                for col = 1:ncols
                    cn = o.data.colInfo[col].name
                    v  = df[!, cn][j]
                    isa(v, AbstractString) || continue
                    if occursin(o.data.searchText, lowercase(v))
                        o.data.currentCol = col; return j
                    end
                end
            end
            return 0
        end
        if searchdfstring(nd.subdataframe) != 0
            if !nd.isOpen; expandnode(nd); ordernode(nd); end
            if !isempty(nd.children)
                substacktmp = copy(substack); push!(substacktmp, 0)
                for (k, c) in enumerate(nd.children)
                    substacktmp[end] = k
                    ret = checknode(c, substacktmp)
                    ret !== nothing && return ret
                end
            else
                therow = searchdfstring(nd.subdataframesorted)
                substacktmp = copy(substack); push!(substacktmp, therow)
                return substacktmp
            end
        end
        return nothing
    end
    while true
        node   = o.data.datalist[i][5]
        isnode = (o.data.datalist[i][3] != :single)
        if isnode && !node.isOpen
            foundstack = checknode(node, o.data.datalist[i][2])
            if foundstack !== nothing
                builddatalist(o.data)
                o.data.currentLine = searchsortedfirst(
                    o.data.datalist, Any[nothing, foundstack],
                    by = y->y[2],
                    lt = (s1, s2)->begin
                        for j = 1:min(length(s1), length(s2))
                            s1[j] == s2[j] && continue
                            return s1[j] < s2[j]
                        end
                        return length(s1) < length(s2)
                    end,
                )
                _dft_check_top!(o); _dft_check_left!(o)
                return o.data.currentLine
            end
        end
        if !isnode
            for col = 1:ncols
                cn = o.data.colInfo[col].name
                v  = node.subdataframesorted[!, cn][o.data.datalist[i][2][end]]
                isa(v, AbstractString) || continue
                if occursin(o.data.searchText, lowercase(v))
                    o.data.currentLine = i; o.data.currentCol = col
                    _dft_check_top!(o); _dft_check_left!(o)
                    return i
                end
            end
        end
        i = mod(i-1+stp, o.data.datalistlen) + 1
        if i == st; beep(); return 0; end
    end
end

function bindings(o::TwObj{TwDfTableData})
    [
        Binding(:esc, "cancel", action = _-> Cancel),
        Binding([" ", :enter, Symbol("return")], "expand/collapse node",
            when   = _-> !isempty(o.data.datalist) && o.data.datalist[o.data.currentLine][3] != :single,
            action = _-> begin
                node = o.data.datalist[o.data.currentLine][5]
                node.isOpen ? (node.isOpen = false) : (expandnode(node); ordernode(node))
                builddatalist(o.data); _dft_check_top!(o)
                Handled
            end),
        Binding("+", "expand all",   action = _-> (_dft_expand_all!(o);   Handled)),
        Binding("-", "collapse all", action = _-> (_dft_collapse_all!(o); Handled)),
        Binding(:up,        "up",           action = _-> (_dft_movev!(o, -1); Handled)),
        Binding(:down,      "down",         action = _-> (_dft_movev!(o,  1); Handled)),
        Binding(:left,      "left col",     action = _-> (_dft_moveh!(o, -1); Handled)),
        Binding(:right,     "right col",    action = _-> (_dft_moveh!(o,  1); Handled)),
        Binding(:ctrl_left,  "page left",   action = _-> (_dft_ctrl_left!(o);  Handled)),
        Binding(:ctrl_right, "page right",  action = _-> (_dft_ctrl_right!(o); Handled)),
        Binding(:ctrl_up,   "prev sibling", action = _-> (_dft_prev_sibling!(o); Handled)),
        Binding(:ctrl_down, "next sibling", action = _-> (_dft_next_sibling!(o); Handled)),
        Binding(:pageup,   "page up",
            action = _-> (_dft_movev!(o, -(_dft_vph(o) - o.data.headerlines)); Handled)),
        Binding(:pagedown, "page down",
            action = _-> (_dft_movev!(o,   _dft_vph(o) - o.data.headerlines);  Handled)),
        Binding(:home, "top-left",
            action = _-> begin
                if o.data.currentTop != 1 || o.data.currentLeft != 1 ||
                   o.data.currentLine != 1 || o.data.currentCol != 1
                    o.data.currentTop = o.data.currentLeft = 1
                    o.data.currentLine = o.data.currentCol = 1
                else
                    beep()
                end
                Handled
            end),
        Binding(Symbol("end"), "bottom",
            action = _-> begin
                vch = _dft_vph(o)
                if o.data.currentTop + vch - 1 < o.data.datalistlen
                    o.data.currentTop  = o.data.datalistlen - vch + 1
                    o.data.currentLine = o.data.datalistlen
                else
                    beep()
                end
                Handled
            end),
        Binding("[", "narrow col",
            action = _-> begin
                w = o.data.colInfo[o.data.currentCol].format.width
                w > 4 ? (o.data.colInfo[o.data.currentCol].format.width = w - 1) : beep()
                Handled
            end),
        Binding("]", "widen col",
            action = _-> begin
                w = o.data.colInfo[o.data.currentCol].format.width
                w < _dft_vpw(o) - 1 ? (o.data.colInfo[o.data.currentCol].format.width = w + 1) : beep()
                Handled
            end),
        Binding("p", "pivot columns",
            action = _-> begin
                allcols = String[string(n) for n in names(o.data.rootnode.subdataframe)]
                append!(allcols, String[string(k) for k in keys(o.data.calcpivots)])
                pvts = String[string(p) for p in o.data.pivots]
                helper = newTwMultiSelect(o.screen.value, allcols,
                    selected=pvts, title="Pivot order", orderable=true, substrsearch=true)
                newpivots = activateTwObj(helper)
                unregisterTwObj(o.screen.value, helper)
                if newpivots !== nothing && newpivots != pvts
                    o.data.pivots = Symbol[Symbol(x) for x in newpivots]
                    o.data.rootnode.children = Any[]
                    o.data.rootnode.isOpen = false
                    expandnode(o.data.rootnode, o.data.initdepth)
                    ordernode(o.data.rootnode)
                    builddatalist(o.data)
                    o.data.currentLine = 1; _dft_check_top!(o)
                end
                Handled
            end),
        Binding("c", "column order",
            action = _-> begin
                allcols    = String[string(n) for n in names(o.data.rootnode.subdataframe)]
                visiblecols = String[string(ci.name) for ci in o.data.colInfo]
                helper = newTwMultiSelect(o.screen.value, allcols,
                    selected=visiblecols, title="Visible columns & their order",
                    orderable=true, substrsearch=true)
                newcols = activateTwObj(helper)
                unregisterTwObj(o.screen.value, helper)
                if newcols !== nothing && newcols != visiblecols
                    o.data.colInfo = TwTableColInfo[]
                    for c in newcols
                        push!(o.data.colInfo, o.data.allcolInfo[Symbol(c)])
                    end
                end
                Handled
            end),
        Binding("v", "views",
            action = _-> begin
                allviews = map(x->x.name, o.data.views)
                helper = newTwPopup(o.screen.value, allviews, substrsearch=true, title="Views")
                vname = activateTwObj(helper)
                unregisterTwObj(o.screen.value, helper)
                if vname !== nothing
                    idx = findfirst(x->x.name == vname, o.data.views)
                    v = o.data.views[idx]
                    o.data.colInfo    = TwTableColInfo[]
                    o.data.pivots     = v.pivots
                    o.data.sortorder  = v.sortorder
                    o.data.initdepth  = v.initdepth
                    for c in v.columns
                        push!(o.data.colInfo, o.data.allcolInfo[Symbol(c)])
                    end
                    o.data.rootnode.children = Any[]
                    o.data.rootnode.isOpen   = false
                    expandnode(o.data.rootnode, o.data.initdepth)
                    ordernode(o.data.rootnode)
                    builddatalist(o.data)
                    o.data.currentLine = 1; _dft_check_top!(o)
                end
                Handled
            end),
        Binding("/", "search forward",
            action = _-> begin
                helper = newTwEntry(o.screen.value, String;
                    width=30, posy=:center, posx=:center, title="Search: ")
                helper.data.inputText = o.data.searchText
                s = activateTwObj(helper)
                unregisterTwObj(o.screen.value, helper)
                if s !== nothing && s != "" && o.data.searchText != s
                    o.data.searchText = s
                    _dft_search_next!(o, 1, true)
                end
                Handled
            end),
        Binding("?", "deep search",
            action = _-> begin
                helper = newTwEntry(o.screen.value, String;
                    width=30, posy=:center, posx=:center, title="Search: ")
                helper.data.inputText = o.data.searchText
                s = activateTwObj(helper)
                unregisterTwObj(o.screen.value, helper)
                if s !== nothing
                    o.data.searchText = s
                    _dft_search_next_deep!(o, true)
                end
                Handled
            end),
        Binding(:ctrl_n, "next match",      action = _-> (_dft_search_next!(o,  1, false); Handled)),
        Binding(:ctrl_b, "prev match",      action = _-> (_dft_search_next!(o, -1, false); Handled)),
        Binding("N",     "deep next match", action = _-> (_dft_search_next_deep!(o, false); Handled)),
        Binding(:ctrl_y, "export",          action = _-> (_dt_export_menu!(o); Handled)),
        Binding(:F2, "describe all cols",
            action = _-> begin
                df_desc = string(DataFrames.describe(o.value))
                tshow(df_desc; title=o.title * " columns", posx=:center, posy=:center)
                Handled
            end),
        Binding(:shift_F2, "describe current col",
            action = _-> begin
                colsym     = o.data.colInfo[o.data.currentCol].name
                d          = DataFrames.describe(o.value, :all, cols=[colsym])
                stat_names = String.(names(d)[2:end])
                stat_vals  = [string(d[1, n]) for n in names(d)[2:end]]
                stats_df   = DataFrame(stat=stat_names, value=stat_vals)
                tshow(stats_df; title=string(colsym) * " full stats",
                      posx=:center, posy=:center, width=50, height=35)
                Handled
            end),
        Binding(:F6, "show cell value",
            action = _-> begin
                colsym = o.data.colInfo[o.data.currentCol].name
                node   = o.data.datalist[o.data.currentLine][5]
                isnode = (o.data.datalist[o.data.currentLine][3] != :single)
                v = isnode ? node[colsym] :
                    node.subdataframesorted[!, colsym][o.data.datalist[o.data.currentLine][2][end]]
                if !ismissing(v) && !in(v, [nothing, Nothing, Any])
                    tshow(v; title=string(colsym), posx=:center, posy=:center)
                end
                Handled
            end),
        Binding(:F3, "column stats",
            action = _-> begin
                colsym = o.data.colInfo[o.data.currentCol].name
                node   = o.data.datalist[o.data.currentLine][5]
                out    = IOBuffer()
                TermWin.describe(out, node.subdataframe[!, colsym])
                if node != o.data.rootnode
                    println(out, "\nRoot table stats")
                    TermWin.describe(out, o.data.rootnode.subdataframe[!, colsym])
                end
                tshow(String(take!(out)); title=string(colsym) * " stats",
                      posx=:center, posy=:center)
                Handled
            end),
    ]
end

function _dft_sel_text(o::TwObj{TwDfTableData})
    o.data.datalistlen == 0 && return ""
    "Row $(o.data.currentLine) / $(o.data.datalistlen)"
end

function inject(o::TwObj{TwDfTableData}, token)
    r = inject_via_table(o, token)
    if r !== Ignored
        if r === Handled
            set!(o.data.selection_text, _dft_sel_text(o))
            refresh(o)
        end
        return r
    end

    if token == :KEY_MOUSE
        (mstate, x, y, _bs) = getmouse()
        vch = _dft_vph(o)
        if mstate == :scroll_up
            _dft_movev!(o, -(round(Int, vch/10))) && refresh(o)
            return Handled
        elseif mstate == :scroll_down
            _dft_movev!(o,  round(Int, vch/10))  && refresh(o)
            return Handled
        elseif mstate == :button1_pressed
            rely, relx = screen_to_relative(o.window, y, x)
            did = false
            if 1<=relx<o.width-1 && o.data.headerlines<rely<o.height-1
                o.data.currentLine = min(
                    o.data.datalistlen,
                    o.data.currentTop + rely - o.borderSizeH + 1 - o.data.headerlines,
                )
                _dft_check_top!(o)
                did = true
            end
            if o.data.datatreewidth+1<relx<o.width-1 && o.data.headerlines<=rely<o.height-1
                widths    = map(x->x.format.width, o.data.colInfo)
                cumwidths = cumsum(map(x->x+1, widths[o.data.currentLeft:end]))
                widthrng  = searchsorted(cumwidths, relx - o.data.datatreewidth - 1)
                o.data.currentCol = min(length(o.data.colInfo), o.data.currentLeft + widthrng.start - 1)
                _dft_check_left!(o)
                did = true
            end
            did && set!(o.data.selection_text, _dft_sel_text(o))
            did && refresh(o)
            return did ? Handled : Ignored
        end
    end
    return Ignored
end

helptext(o::TwObj{TwDfTableData}) = helptext_from_bindings(o)

function clamp_scroll!(o::TwObj{TwDfTableData})
    updateTableDimensions(o)
    vh = o.height - 2 * o.borderSizeV - o.data.headerlines
    vw = o.width - 2 * o.borderSizeH - o.data.datatreewidth
    if vh < 1 || vw < 1
        return
    end
    # Vertical
    if o.data.datalistlen > 0
        if o.data.currentLine < 1
            o.data.currentLine = 1
        elseif o.data.currentLine > o.data.datalistlen
            o.data.currentLine = o.data.datalistlen
        end
        if o.data.currentTop < 1
            o.data.currentTop = 1
        elseif o.data.currentTop > max(1, o.data.datalistlen - vh + 1)
            o.data.currentTop = max(1, o.data.datalistlen - vh + 1)
        end
        if o.data.currentTop > o.data.currentLine
            o.data.currentTop = o.data.currentLine
        elseif o.data.currentLine - o.data.currentTop > vh - 1
            o.data.currentTop = o.data.currentLine - vh + 1
        end
    end
    # Horizontal: ensure currentLeft fits.
    ncols = length(o.data.colInfo)
    if ncols > 0
        if o.data.currentCol < 1
            o.data.currentCol = 1
        elseif o.data.currentCol > ncols
            o.data.currentCol = ncols
        end
        widths = map(x->x.format.width, o.data.colInfo)
        revcumwidths = cumsum(map(x->x+1, reverse(widths)))
        widthrng = searchsorted(revcumwidths, vw)
        maxLeft = ncols - widthrng.stop + 1
        if o.data.currentLeft > maxLeft
            o.data.currentLeft = max(1, maxLeft)
        end
        if o.data.currentLeft < 1
            o.data.currentLeft = 1
        end
        if o.data.currentLeft > o.data.currentCol
            o.data.currentLeft = o.data.currentCol
        end
    end
end
