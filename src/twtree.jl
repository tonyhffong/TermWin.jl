defaultTreeBottomText = "F1:help <spc><rtn>:toggle F5:string F6:popup F7:SaveGlobal +/-:exp&collaps /:search"

modulenames = Dict{Module,Array{Symbol,1}}()
moduleallnames = Dict{Module,Array{Symbol,1}}()
typefields = Dict{Any,Array{Symbol,1}}()

typefields[Method] = [:sig, :isstaged]
typefields[Core.CodeInfo] = [:code, :slotnames, :slottypes]
typefields[DataType] = [:name, :super, :abstract, :mutable, :parameters]
typefields[Type] = [:name, :module, :primary]

treeTypeMaxWidth = 30
treeValueMaxWidth = 400

mutable struct TwTreeData
    openstatemap::Dict{Any,Bool}
    datalist::Vector{TreeRow}    # typed rows (was an anonymous 6-tuple)
    datalistlen::Int
    datatreewidth::Int
    datatypewidth::Int
    datavaluewidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool # e.g.1/100 1.0% at top right corner
    bottomText::String
    showHelp::Bool
    searchText::String
    moduleall::Bool
    selection_text::Observable{String}
    function TwTreeData()
        log("TwTreeData 0")
        rv = new(
            Dict{Any,Bool}(),
            TreeRow[],
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            true,
            "",
            true,
            "",
            true,
            Observable(""),
        )
        log("TwTreeData 1")
        return (rv)
    end
end

function newTwTree(
    scr::TwObj,
    ex;
    height::Real = 1.0,
    width::Real = 1.0,
    posy::Any = :staggered,
    posx::Any = :staggered,
    title::String = string(typeof(ex)),
    box::Bool = true,
    showLineInfo::Bool = true,
    showHelp::Bool = true,
    bottomText::String = defaultTreeBottomText,
)
    log("newTwTree 0")
    obj = TwObj(TwTreeData(), Val{:Tree})
    log("newTwTree 1")
    obj.value = ex
    obj.title = title
    obj.box = box
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 2 : 0
    obj.data.openstatemap[Any[]] = true
    log("newTwTree 2")
    tree_data(ex, title, obj.data.datalist, obj.data.openstatemap, Any[], Int[], true)
    log("newTwTree 3")
    updateTreeDimensions(obj)
    obj.data.showLineInfo = showLineInfo
    obj.data.showHelp = showHelp
    obj.data.bottomText = bottomText

    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

# x is the value, name is a pretty-print identifier
# stack is the pathway to get to x so far
# skiplines are hints where we should not draw the vertical lines to the left
# because it corresponds the end of some list at a lower depth level

function tree_data(
    x::Any,
    name::String,
    list::Array{T,1},
    openstatemap::Dict{Any,Bool},
    stack::Array{Any,1},
    skiplines::Array{Int,1} = Int[],
    moduleall::Bool = true,
) where {T}
    global modulenames, typefields
    isexp = haskey(openstatemap, stack) && openstatemap[stack]
    typx = typeof(x)

    log("tree leaf name=" * string(name) * " depth=" * string(length(list)))
    intern_tree_data =
        (
            subx,
            subn,
            substack,
            islast,
        )->begin
            log(string(subn) * " type=" * string(typeof(subn)))
            if islast
                newskip = copy(skiplines)
                push!(newskip, length(stack) + 1)
                tree_data(subx, subn, list, openstatemap, substack, newskip)
            else
                tree_data(subx, subn, list, openstatemap, substack, skiplines)
            end
        end
    if typx == Symbol ||
       typx <: Number ||
       typx == Any ||
       (typx == DataType && !isempty(stack)) || # so won't expand deep
       typx <: Ptr ||
       typx <: AbstractString ||
       typx <: Dates.TimeType
        s = string(name)
        t = string(typx)
        if typx <: Integer && typx <: Unsigned
            v = @sprintf("0x%x", x)
        elseif typx == Symbol
            v = repr_symbol(x)
        elseif typx <: AbstractString
            v = escape_string(x)
        else
            v = string(x)
        end
        push!(list, TreeRow(s, t, v, stack, :single, skiplines))
    elseif typx == WeakRef
        s = string(name)
        t = string(typx)
        v = x.value === nothing ? "<nothing>" : @sprintf("id:0x%x", object_id(x.value))
        push!(list, TreeRow(s, t, v, stack, :single, skiplines))
    elseif typx <: Array || typx <: Tuple || typx <: Core.SimpleVector
        s = string(name)
        len = length(x)
        if typx <: Tuple
            if len <= 2
                t = string(typx)
            else
                t = "Tuple"
            end
        else
            t = string(typx)
        end
        szstr = string(len)
        v = "size=" * szstr
        expandhint = isempty(x) ? :single : (isexp ? :open : :close)
        push!(list, TreeRow(s, t, v, stack, expandhint, skiplines))
        if isexp
            szdigits = length(szstr)
            for (i, a) in enumerate(x)
                istr = string(i)
                subname = "[" * repeat(" ", szdigits - length(istr)) * istr * "]"
                newstack = copy(stack)
                push!(newstack, i)
                intern_tree_data(a, subname, newstack, i==len)
            end
        end
    elseif isa(x, AbstractDict)
        s = string(name)
        t = string(typx)
        len = length(x)
        szstr = string(len)
        v = "size=" * szstr
        expandhint = isempty(x) ? :single : (isexp ? :open : :close)
        push!(list, TreeRow(s, t, v, stack, expandhint, skiplines))
        if isexp
            ktype = keytype(x)
            ks = collect(keys(x))
            if ktype <: Real || ktype <: AbstractString || ktype == Symbol
                sort!(ks)
            end
            for (i, k) in enumerate(ks)
                v = x[k]
                if ktype == Symbol
                    subname = repr_symbol(k)
                else
                    subname = repr(k)
                end
                newstack = copy(stack)
                push!(newstack, k)
                intern_tree_data(v, subname, newstack, i==len)
            end
        end
    elseif typx == Function
        s = string(name)
        t = string(typx)
        mt = methods(x)
        len = length(mt)
        szstr = string(len)
        v = "num methods=" * szstr
        #v = "*"
        expandhint = len==0 ? :single : (isexp ? :open : :close)
        push!(list, TreeRow(s, t, v, stack, expandhint, skiplines))
        if isexp
            szdigits = length(szstr)
            for (i, m) in enumerate(mt)
                istr = string(i)
                subname = "Method[" * repeat(" ", szdigits - length(istr)) * istr * "]"
                newstack = copy(stack)
                push!(newstack, i)
                intern_tree_data(m, subname, newstack, i==len)
            end
        end
    elseif typx == Module && !isempty(stack) # don't want to recursively descend
        s = string(name)
        t = string(typx)
        v = string(x)
        push!(list, TreeRow(s, t, v, stack, :single, skiplines))
    else
        log("  " * string(typx))
        ns = Symbol[]
        if typx == Module
            if moduleall
                if haskey(moduleallnames, x)
                    ns = moduleallnames[x]
                else
                    ns = filter(y->!startswith(string(y), "@"), names(x, all = true))
                    sort!(ns)
                    moduleallnames[x] = ns
                end
            else
                if haskey(modulenames, x)
                    ns = modulenames[x]
                else
                    ns = filter(y->!startswith(string(y), "@"), names(x))
                    sort!(ns)
                    modulenames[x] = ns
                end
            end
        else
            if haskey(typefields, typx)
                ns = typefields[typx]
            else
                try
                    ns = collect(fieldnames(typx))
                    if length(ns) > 20
                        sort!(ns)
                    end
                catch
                end
                typefields[typx] = ns
            end
        end
        s = string(name)
        expandhint = isempty(ns) ? :single : (isexp ? :open : :close)
        t = string(typx)
        v = string(x)
        len = length(ns)
        push!(list, TreeRow(s, t, v, stack, expandhint, skiplines))
        if isexp && !isempty(ns)
            for (i, n) in enumerate(ns)
                subname = string(n)
                newstack = copy(stack)
                push!(newstack, n)
                try
                    v = getfield(x, n)
                    intern_tree_data(v, subname, newstack, i==len)
                catch err
                    intern_tree_data(ErrorException(string(err)), subname, newstack, i==len)
                    if typx == Module
                        if moduleall
                            todel = findall(y->y==n, moduleallnames[x])
                            deleteat!(moduleallnames[x], todel[1])
                        else
                            todel = findall(y->y==n, modulenames[x])
                            deleteat!(modulenames[x], todel[1])
                        end
                    else
                        todel = findall(y->y==n, typefields[typx])
                        deleteat!(typefields[typx], todel[1])
                    end
                end
            end
        end
    end
end

function getvaluebypath(x, path)
    if isempty(path)
        return x
    end
    key = popfirst!(path)
    if typeof(x) <: Array || isa(x, AbstractDict) || typeof(x) <: Tuple || typeof( x ) <: Core.SimpleVector
        return getvaluebypath(x[key], path)
    elseif typeof(x) == Function
        mt = methods(x)
        for (i, m) in enumerate(mt)
            if i == key
                return getvaluebypath(m, path)
            end
        end
        return nothing
    else
        return getvaluebypath(getfield(x, key), path)
    end
end

function _tree_update_data!(o::TwObj{TwTreeData})
    o.data.datalist = TreeRow[]
    tree_data(o.value, o.title, o.data.datalist, o.data.openstatemap, Any[], Int[], o.data.moduleall)
    updateTreeDimensions(o)
end

function _tree_checkTop!(o::TwObj{TwTreeData})
    vh = o.height - 2 * o.borderSizeV
    if o.data.currentTop < 1
        o.data.currentTop = 1
    elseif o.data.currentTop > o.data.datalistlen - vh + 1
        o.data.currentTop = max(1, o.data.datalistlen - vh + 1)
    end
    if o.data.currentTop > o.data.currentLine
        o.data.currentTop = o.data.currentLine
    elseif o.data.currentLine - o.data.currentTop > vh - 1
        o.data.currentTop = o.data.currentLine - vh + 1
    end
end

function _tree_moveby!(o::TwObj{TwTreeData}, n::Int)
    oldline = o.data.currentLine
    o.data.currentLine = max(1, min(o.data.datalistlen, o.data.currentLine + n))
    if oldline != o.data.currentLine
        _tree_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _tree_search_next!(o::TwObj{TwTreeData}, step::Int, trivialstop::Bool)
    st = o.data.currentLine
    o.data.searchText = lowercase(o.data.searchText)
    vh = o.height - 2 * o.borderSizeV
    i = trivialstop ? st : (mod(st-1+step, o.data.datalistlen) + 1)
    while true
        if occursin(o.data.searchText, lowercase(o.data.datalist[i].name)) ||
           occursin(o.data.searchText, lowercase(o.data.datalist[i].valuestr))
            o.data.currentLine = i
            if abs(i-st) > vh
                o.data.currentTop = o.data.currentLine - (vh >> 1)
            end
            _tree_checkTop!(o)
            return i
        end
        i = mod(i-1+step, o.data.datalistlen) + 1
        if i == st
            beep()
            return 0
        end
    end
end

function _tree_toggle_expand!(o::TwObj{TwTreeData})
    expandhint = o.data.datalist[o.data.currentLine].expandhint
    expandhint == :single && return
    stck = o.data.datalist[o.data.currentLine].stack
    o.data.openstatemap[stck] = !(get(o.data.openstatemap, stck, false))
    _tree_update_data!(o)
end

function _tree_expand_all!(o::TwObj{TwTreeData})
    currentstack = o.data.datalist[o.data.currentLine].stack
    somethingchanged = false
    for i = 1:o.data.datalistlen
        if o.data.datalist[i].expandhint != :single
            stck = o.data.datalist[i].stack
            if !get(o.data.openstatemap, stck, false)
                o.data.openstatemap[stck] = true
                somethingchanged = true
            end
        end
    end
    if somethingchanged
        vh = o.height - 2 * o.borderSizeV
        prevline = o.data.currentLine
        _tree_update_data!(o)
        for i = o.data.currentLine:o.data.datalistlen
            if currentstack == o.data.datalist[i].stack
                o.data.currentLine = i
                abs(i - prevline) > vh && (o.data.currentTop = i - round(Int, vh/2))
                break
            end
        end
        _tree_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _tree_collapse_deepest!(o::TwObj{TwTreeData})
    currentstack = copy(o.data.datalist[o.data.currentLine].stack)
    maxstackdepth = maximum(map(x->length(x.stack), o.data.datalist))
    maxstackdepth <= 1 && (beep(); return)
    somethingchanged = false
    for i = 1:o.data.datalistlen
        stck = o.data.datalist[i].stack
        if o.data.datalist[i].expandhint != :single && length(stck) == maxstackdepth-1
            if get(o.data.openstatemap, stck, false)
                o.data.openstatemap[stck] = false
                somethingchanged = true
            end
        end
    end
    if somethingchanged
        vh = o.height - 2 * o.borderSizeV
        _tree_update_data!(o)
        length(currentstack) == maxstackdepth && pop!(currentstack)
        prevline = o.data.currentLine
        o.data.currentLine = 1
        for i = 1:min(prevline, o.data.datalistlen)
            if currentstack == o.data.datalist[i].stack
                o.data.currentLine = i
                abs(i-prevline) > vh && (o.data.currentTop = i - round(Int, vh/2))
                break
            end
        end
        _tree_checkTop!(o)
    else
        beep()
    end
end

function _tree_collapse_all!(o::TwObj{TwTreeData})
    currentstack = copy(o.data.datalist[o.data.currentLine].stack)
    length(currentstack) > 1 && (currentstack = Any[currentstack[1]])
    o.data.openstatemap = Dict{Any,Bool}(Any[] => true)
    _tree_update_data!(o)
    vh = o.height - 2 * o.borderSizeV
    prevline = o.data.currentLine
    o.data.currentLine = 1
    for i = 1:min(prevline, o.data.datalistlen)
        if currentstack == o.data.datalist[i].stack
            o.data.currentLine = i
            abs(i-prevline) > vh && (o.data.currentTop = o.data.currentLine - round(Int, vh/2))
            break
        end
    end
    _tree_checkTop!(o)
end

function _tree_toggle_module!(o::TwObj{TwTreeData})
    o.data.moduleall = !o.data.moduleall
    prevstack = copy(o.data.datalist[o.data.currentLine].stack)
    _tree_update_data!(o)
    maxmatch = 0
    bestline = 0
    for i = 1:o.data.datalistlen
        stck = o.data.datalist[i].stack
        if length(prevstack) > maxmatch &&
           length(stck) > maxmatch &&
           isequal(prevstack[1:(maxmatch+1)], stck[1:(maxmatch+1)])
            maxmatch += 1
            bestline = i
            continue
        elseif length(prevstack) < maxmatch
            break
        elseif length(prevstack) >= maxmatch &&
               length(stck) >= maxmatch &&
               !isequal(prevstack[1:maxmatch], stck[1:maxmatch])
            break
        end
    end
    o.data.currentLine = max(1, bestline)
    _tree_checkTop!(o)
end

function updateTreeDimensions(o::TwObj)
    global treeTypeMaxWidth, treeValueMaxWidth

    o.data.datalistlen = length(o.data.datalist)
    o.data.datatreewidth =
        maximum(map(x->length(x.name) + 1 + 2 * length(x.stack), o.data.datalist))
    o.data.datatypewidth =
        min(treeTypeMaxWidth, max(15, maximum(map(x->length(x.typestr), o.data.datalist))))
    o.data.datavaluewidth =
        maximum(map(x->length(x.valuestr), o.data.datalist))
    nothing
end

function draw(o::TwObj{TwTreeData})
    updateTreeDimensions(o)
    viewContentHeight = o.height - 2 * o.borderSizeV
    viewContentWidth = o.width - 2 * o.borderSizeV

    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        titlestr = o.title
        if typeof(o.value) == Module
            if o.data.moduleall
                titlestr *= "(all names)"
            else
                titlestr *= "(exported )"
            end
        end
        mvwprintw(o.window, 0, max(0, round(Int, (o.width - length(titlestr))/2)), "%s", titlestr)
    end
    if o.data.showLineInfo && o.box
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
        mvwprintw(o.window, 0, max(0, o.width - length(msg)-3), "%s", msg)
    end
    for r = o.data.currentTop:min(o.data.currentTop+viewContentHeight-1, o.data.datalistlen)

        stacklen = length(o.data.datalist[r].stack)
        s = ensure_length(
            repeat(" ", 2*stacklen + 1) * o.data.datalist[r].name,
            o.data.datatreewidth,
        )
        t = ensure_length(o.data.datalist[r].typestr, o.data.datatypewidth)
        log(o.data.datalist[r].name)
        log(o.data.datalist[r].valuestr)
        v = ensure_length(
            o.data.datalist[r].valuestr,
            viewContentWidth-o.data.datatreewidth - o.data.datatypewidth-3,
            false,
        )

        if r == o.data.currentLine
            wattron(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end
        mvwprintw(o.window, 1+r-o.data.currentTop, 2, "%s", s)
        mvwaddch(o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth, get_acs_val('x'))
        mvwprintw(o.window, 1+r-o.data.currentTop, 2+o.data.datatreewidth+1, "%s", t)
        mvwaddch(
            o.window,
            1+r-o.data.currentTop,
            2+o.data.datatreewidth+o.data.datatypewidth+1,
            get_acs_val('x'),
        )
        mvwprintw(
            o.window,
            1+r-o.data.currentTop,
            2+o.data.datatreewidth+o.data.datatypewidth+2,
            "%s",
            v,
        )

        for i = 1:(stacklen-1)
            if !in(i, o.data.datalist[r].skiplines) # skiplines
                mvwaddch(o.window, 1+r-o.data.currentTop, 2*i, get_acs_val('x')) # vertical line
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t') # tee pointing right
            if r == o.data.datalistlen ||  # end of the whole thing
               length(o.data.datalist[r+1].stack) < stacklen || # next one is going back in level
               (
                   length(o.data.datalist[r+1].stack) > stacklen &&
                   in(stacklen, o.data.datalist[r+1].skiplines)
               ) # going deeping in level
                contchar = get_acs_val('m') # LL corner
            end
            mvwaddch(o.window, 1+r-o.data.currentTop, 2*stacklen, contchar)
            mvwaddch(o.window, 1+r-o.data.currentTop, 2*stacklen+1, get_acs_val('q')) # horizontal line
        end
        if o.data.datalist[r].expandhint == :close
            mvwprintw(
                o.window,
                1+r-o.data.currentTop,
                2*stacklen+2,
                "%s",
                string(Char(0x25b8)),
            ) # right-pointing small triangle
        elseif o.data.datalist[r].expandhint == :open
            mvwprintw(
                o.window,
                1+r-o.data.currentTop,
                2*stacklen+2,
                "%s",
                string(Char(0x25be)),
            ) # down-pointing small triangle
        end

        if r == o.data.currentLine
            wattroff(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end
    end
    if length(o.data.bottomText) != 0 && o.box
        mvwprintw(
            o.window,
            o.height-1,
            max(0, round(Int, (o.width - length(o.data.bottomText))/2)),
            "%s",
            o.data.bottomText,
        )
    end
end

function bindings(o::TwObj{TwTreeData})
    [
        Binding(:esc, "cancel", action = _->Cancel),
        Binding([" ", :enter, Symbol("return")], "toggle expand",
                action = _->(_tree_toggle_expand!(o); Handled)),
        Binding("+", "expand all",     action = _->(_tree_expand_all!(o); Handled)),
        Binding("-", "collapse level", action = _->(_tree_collapse_deepest!(o); Handled)),
        Binding("_", "collapse all",   action = _->(_tree_collapse_all!(o); Handled)),
        Binding("m", "toggle exports",
                when   = _-> typeof(o.value) == Module,
                action = _->(_tree_toggle_module!(o); Handled)),
        Binding(:F5, "show as string",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, copy(stck))
                    if v isa Expr
                        tshow(exprstring(v), "julia"; title = string(lastkey))
                    else
                        tshow(string(v); title = string(lastkey))
                    end
                    Handled
                end),
        Binding(:F6, "popup value",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, stck)
                    if typeof(v) == Method
                        try
                            f = getfield(v.module, v.name)
                            edit(f, v.sig)
                        catch err
                            tshow("Error showing Method\n" * string(err), title = string(lastkey))
                        end
                    elseif !in(v, [nothing, Nothing, Any])
                        tshow(v, title = string(lastkey))
                    end
                    Handled
                end),
        Binding(:shift_F6, "popup type",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    v = getvaluebypath(o.value, stck)
                    !in(v, [nothing, Nothing, Any]) && tshow(typeof(v))
                    Handled
                end),
        Binding(:F7, "pin to scratchpad",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, stck)
                    helper = newTwEntry(
                        o.screen.value, String;
                        width = 34, posy = :center, posx = :center,
                        title = "Pin to scratchpad as: ",
                    )
                    helper.data.inputText = string(lastkey)
                    helper.data.cursorPos = length(helper.data.inputText) + 1
                    varname = activateTwObj(helper)
                    unregisterTwObj(o.screen.value, helper)
                    if varname !== nothing && !isempty(strip(varname))
                        pin!(strip(varname), v)
                    end
                    Handled
                end),
        Binding(:up,   "up",   action = _->(_tree_moveby!(o, -1); Handled)),
        Binding(:down, "down", action = _->(_tree_moveby!(o,  1); Handled)),
        Binding(:ctrl_left, "parent",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :parent)
                    moved ? (o.data.currentLine = target; _tree_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_up, "prev sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :prev_sibling)
                    moved ? (o.data.currentLine = target; _tree_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_down, "next sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :next_sibling)
                    moved ? (o.data.currentLine = target; _tree_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:pageup,   "page up",
                action = _->(_tree_moveby!(o, -(o.height - 2*o.borderSizeV)); Handled)),
        Binding(:pagedown, "page down",
                action = _->(_tree_moveby!(o,  o.height - 2*o.borderSizeV); Handled)),
        Binding(:home, "go to start",
                action = _->begin
                    if o.data.currentTop != 1 || o.data.currentLeft != 1 || o.data.currentLine != 1
                        o.data.currentTop = 1; o.data.currentLeft = 1; o.data.currentLine = 1
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(Symbol("end"), "go to end",
                action = _->begin
                    vh = o.height - 2 * o.borderSizeV
                    if o.data.currentTop + vh - 1 < o.data.datalistlen
                        o.data.currentTop = o.data.datalistlen - vh + 1
                        o.data.currentLine = o.data.datalistlen
                    else
                        beep()
                    end
                    Handled
                end),
        Binding("/", "search",
                action = _->begin
                    helper = newTwEntry(
                        o.screen.value, String;
                        width = 30, posy = :center, posx = :center,
                        title = "Search: ",
                    )
                    helper.data.inputText = o.data.searchText
                    s = activateTwObj(helper)
                    unregisterTwObj(o.screen.value, helper)
                    if s !== nothing && s != "" && o.data.searchText != s
                        o.data.searchText = s
                        _tree_search_next!(o, 1, true)
                    end
                    Handled
                end),
        Binding(["n", :ctrl_n], "next match",
                action = _->(o.data.searchText != "" && _tree_search_next!(o,  1, false); Handled)),
        Binding(["p", "N", :ctrl_p], "prev match",
                action = _->(o.data.searchText != "" && _tree_search_next!(o, -1, false); Handled)),
        Binding("L", "mid → end",
                action = _->begin
                    target = min(round(Int, ceil((o.data.currentLine + o.data.datalistlen)/2)), o.data.datalistlen)
                    target != o.data.currentLine ? (o.data.currentLine = target; _tree_checkTop!(o)) : beep()
                    Handled
                end),
        Binding("l", "mid → start",
                action = _->begin
                    target = max(round(Int, floor(o.data.currentLine / 2)), 1)
                    target != o.data.currentLine ? (o.data.currentLine = target; _tree_checkTop!(o)) : beep()
                    Handled
                end),
    ]
end

function _tw_tree_sel_text(o::TwObj{TwTreeData})
    isempty(o.data.datalist) && return ""
    row = o.data.datalist[clamp(o.data.currentLine, 1, length(o.data.datalist))]
    "$(row.name) :: $(row.typestr)"
end

function inject(o::TwObj{TwTreeData}, token)
    r = inject_via_table(o, token)
    if r === Handled
        set!(o.data.selection_text, _tw_tree_sel_text(o))
        refresh(o)
        return r
    end
    r !== Ignored && return r

    # h-scroll and mouse (undocumented)
    vcw = o.data.datatreewidth + o.data.datatypewidth + o.data.datavaluewidth + 2
    if token == :left
        if o.data.currentLeft > 1
            o.data.currentLeft -= 1; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :right
        if o.data.currentLeft + o.width - 2*o.borderSizeH < vcw
            o.data.currentLeft += 1; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        vh = o.height - 2 * o.borderSizeV
        if mstate == :scroll_up
            _tree_moveby!(o, -(round(Int, vh/5))); refresh(o)
        elseif mstate == :scroll_down
            _tree_moveby!(o,  round(Int, vh/5));  refresh(o)
        elseif mstate == :button1_pressed
            begy, begx = getwinbegyx(o.window)
            relx = x - begx
            rely = y - begy
            if 0 <= relx < o.width && 0 <= rely < o.height
                o.data.currentLine = o.data.currentTop + rely - o.borderSizeH + 1
                set!(o.data.selection_text, _tw_tree_sel_text(o))
                refresh(o)
            else
                return Ignored
            end
        end
        return Handled
    end

    return Ignored
end

helptext(o::TwObj{TwTreeData}) = o.data.showHelp ? helptext_from_bindings(o) : ""

function clamp_scroll!(o::TwObj{TwTreeData})
    updateTreeDimensions(o)
    vh = o.height - 2 * o.borderSizeV
    if vh < 1
        return
    end
    if o.data.currentLine < 1
        o.data.currentLine = 1
    elseif o.data.currentLine > o.data.datalistlen
        o.data.currentLine = max(1, o.data.datalistlen)
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
