# twdicttree.jl — editable tree viewer for Dict/Vector structures


defaultDictTreeBottomText = "F1:help e:edit Ctrl-N:add Ctrl-D:del r:rename Alt-↑↓:move F10:submit"

const _DT_TYPE_NAMES = String[
    "String",
    "Int64",
    "Float64",
    "Bool",
    "Date",
    "Dict{String,Any}",
    "Dict{Symbol,Any}",
    "Dict{Any,Any}",
    "Vector{Any}",
    "Vector{String}",
    "Vector{Int64}",
    "Vector{Float64}",
]

const _DT_TYPE_MAP = Dict{String,DataType}(
    "String"           => String,
    "Int64"            => Int64,
    "Float64"          => Float64,
    "Bool"             => Bool,
    "Date"             => Dates.Date,
    "Dict{String,Any}" => Dict{String,Any},
    "Dict{Symbol,Any}" => Dict{Symbol,Any},
    "Dict{Any,Any}"    => Dict{Any,Any},
    "Vector{Any}"      => Vector{Any},
    "Vector{String}"   => Vector{String},
    "Vector{Int64}"    => Vector{Int64},
    "Vector{Float64}"  => Vector{Float64},
)

mutable struct TwDictTreeData
    # tree display (mirrors TwTreeData fields)
    openstatemap::Dict{Any,Bool}
    datalist::Vector{TreeRow}    # typed rows, built by the shared tree_data
    datalistlen::Int
    datatreewidth::Int
    datatypewidth::Int
    datavaluewidth::Int
    currentTop::Int
    currentLine::Int
    currentLeft::Int
    showLineInfo::Bool
    bottomText::String
    showHelp::Bool
    searchText::String
    # inline edit state
    isEditing::Bool
    editor::InlineEditor    # the active leaf's inline editor (state + parse/format)
    history::EditHistory{Any}
    selection_text::Observable{String}
    isScratchpad::Bool
end

function newTwDictTree(
    scr::TwObj,
    ex::AbstractDict;
    height::SizeSpec  = 1.0,
    width::SizeSpec   = 1.0,
    posy::Any     = :staggered,
    posx::Any     = :staggered,
    title::String = string(typeof(ex)),
    box::Bool     = true,
    showLineInfo::Bool = true,
    showHelp::Bool     = true,
    bottomText::String = defaultDictTreeBottomText,
    key::Union{Nothing,Symbol} = nothing,
)
    data = TwDictTreeData(
        Dict{Any,Bool}(), TreeRow[],
        0, 0, 0, 0,
        1, 1, 1,
        showLineInfo, bottomText, showHelp, "",
        false, InlineEditor(String; width = 1),
        EditHistory{Any}(deepcopy(ex)),
        Observable(""),
        false,
    )
    obj = TwObj(data, Val{:DictTree})
    obj.value   = deepcopy(ex)
    obj.title   = title
    obj.box     = box
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 2 : 0
    obj.formkey = key
    data.openstatemap[Any[]] = true
    tree_data(obj.value, title, data.datalist, data.openstatemap, Any[], Int[], true)
    _dt_update_dimensions!(obj)
    link_parent_child(scr, obj, height, width, posy, posx)
    obj
end

# ─── dimension helpers ────────────────────────────────────────────────────────

function _dt_update_dimensions!(o::TwObj{TwDictTreeData})
    data = o.data
    data.datalistlen = length(data.datalist)
    isempty(data.datalist) && return
    data.datatreewidth  = maximum(map(x -> length(x.name) + 1 + 2*length(x.stack), data.datalist))
    data.datatypewidth  = min(treeTypeMaxWidth, max(15, maximum(map(x -> length(x.typestr), data.datalist))))
    data.datavaluewidth = maximum(map(x -> length(x.valuestr), data.datalist))
end

# Natural content extent for :content / :fill layout sizing.
function natural_height(o::TwObj{TwDictTreeData})
    isempty(o.data.datalist) && return o.height
    _dt_update_dimensions!(o)
    o.data.datalistlen + 2 * o.borderSizeV
end
function natural_width(o::TwObj{TwDictTreeData})
    isempty(o.data.datalist) && return o.width
    _dt_update_dimensions!(o)
    o.data.datatreewidth + o.data.datatypewidth + o.data.datavaluewidth + 2 + 2 * o.borderSizeH
end

function _dt_view_dims(o::TwObj{TwDictTreeData})
    viewH = o.height - 2 * o.borderSizeV
    viewW = o.width  - 2 * o.borderSizeV   # intentional: mirrors twtree convention
    fieldW = max(8, viewW - o.data.datatreewidth - o.data.datatypewidth - 3)
    (viewH, viewW, fieldW)
end

function _dt_checkTop!(o::TwObj{TwDictTreeData})
    data = o.data
    (viewH, _, _) = _dt_view_dims(o)
    if data.currentTop < 1; data.currentTop = 1; end
    if data.currentTop > max(1, data.datalistlen - viewH + 1)
        data.currentTop = max(1, data.datalistlen - viewH + 1)
    end
    if data.currentTop > data.currentLine
        data.currentTop = data.currentLine
    elseif data.currentLine - data.currentTop > viewH - 1
        data.currentTop = data.currentLine - viewH + 1
    end
end

_dt_snapshot!(o::TwObj{TwDictTreeData}) = push_snapshot!(o.data.history, deepcopy(o.value))

function _dt_update_data!(o::TwObj{TwDictTreeData})
    data = o.data
    data.datalist = TreeRow[]
    tree_data(o.value, o.title, data.datalist, data.openstatemap, Any[], Int[], true)
    _dt_update_dimensions!(o)
end

function setvalue!(o::TwObj{TwDictTreeData}, d::AbstractDict)
    o.value = d
    _dt_update_data!(o)
    o.data.currentLine = clamp(o.data.currentLine, 1, max(1, o.data.datalistlen))
end

function _dt_find_and_goto!(o::TwObj{TwDictTreeData}, target_stack)
    data = o.data
    for i = 1:data.datalistlen
        if data.datalist[i].stack == target_stack
            data.currentLine = i
            _dt_checkTop!(o)
            return true
        end
    end
    data.currentLine = max(1, min(data.currentLine, data.datalistlen))
    _dt_checkTop!(o)
    return false
end

# ─── inline edit helpers ─────────────────────────────────────────────────────

function _dt_value_to_buf(val)::String
    val === nothing && return ""
    val === missing && return ""
    vt = typeof(val)
    vt <: AbstractString && return val
    vt <: Dates.Date     && return Dates.format(val, "yyyy-mm-dd")
    return string(val)
end

function _dt_begin_edit!(o::TwObj{TwDictTreeData})
    data = o.data
    row = data.datalist[data.currentLine]
    expandhint = row.expandhint
    expandhint != :single && return false   # containers not inline-editable

    stack = row.stack
    val = getvaluebypath(o.value, copy(stack))
    vt  = typeof(val)
    (vt <: AbstractString || vt <: Number || vt == Bool || vt <: Dates.Date) || return false

    (_, _, fieldW) = _dt_view_dims(o)
    data.editor = InlineEditor(vt; width = fieldW)
    # Seed the buffer with the dict tree's plain string rendering (it shows
    # numbers as `string(val)`, not grouped) rather than editor_load!'s formatter.
    data.editor.buffer = _dt_value_to_buf(val)
    data.editor.cursorPos = length(data.editor.buffer) + 1
    data.isEditing = true
    return true
end

function _dt_commit_edit!(o::TwObj{TwDictTreeData})
    data = o.data
    row  = data.datalist[data.currentLine]
    stack = row.stack

    (_, _, fieldW) = _dt_view_dims(o)
    data.editor.width = fieldW
    (val, ok) = editor_commit(data.editor)
    if !ok
        return false   # editor_commit set data.editor.incomplete
    end

    # write back into the live dict
    _dt_set_value_at_path!(o.value, stack, val)
    data.isEditing = false
    _dt_update_data!(o)
    _dt_snapshot!(o)
    return true
end

# ─── path manipulation ────────────────────────────────────────────────────────

function _dt_set_value_at_path!(root, path::Vector, val)
    isempty(path) && return
    parent = getvaluebypath(root, copy(path[1:end-1]))
    key    = path[end]
    if isa(parent, AbstractDict)
        parent[key] = val
    elseif isa(parent, AbstractVector)
        parent[key] = val
    end
end

function _dt_delete_at_path!(root, path::Vector)
    isempty(path) && return false
    parent = getvaluebypath(root, copy(path[1:end-1]))
    key    = path[end]
    if isa(parent, AbstractDict)
        delete!(parent, key)
        return true
    elseif isa(parent, AbstractVector) && isa(key, Integer)
        deleteat!(parent, key)
        return true
    end
    return false
end

# ─── structural operation dialogs ─────────────────────────────────────────────

function _dt_ask_type!(scr::TwObj)
    popup = newTwPopup(
        scr, _DT_TYPE_NAMES;
        posy = :center, posx = :center,
        title = "Value type",
        substrsearch = true,
        maxheight = length(_DT_TYPE_NAMES) + 2,
        maxwidth = 28,
    )
    result = activateTwObj(popup)
    unregisterTwObj(scr, popup)
    result === nothing && return nothing
    return get(_DT_TYPE_MAP, result, nothing)
end

function _dt_ask_value!(scr::TwObj, vtype::DataType)
    if vtype <: AbstractDict || vtype <: AbstractVector
        return (vtype(), true)
    elseif vtype == Bool
        popup = newTwPopup(scr, ["true", "false"]; posy = :center, posx = :center, title = "Value")
        result = activateTwObj(popup)
        unregisterTwObj(scr, popup)
        result === nothing && return (nothing, false)
        return (result == "true", true)
    else
        entry = newTwEntry(scr, vtype; width = 32, posy = :center, posx = :center,
                           title = "Value: ", box = true)
        if vtype <: Number
            entry.data.inputText = "0"
            entry.data.cursorPos = 2
        elseif vtype <: Dates.Date
            entry.data.inputText = Dates.format(Dates.today(), "yyyy-mm-dd")
            entry.data.cursorPos = 11
        end
        result = activateTwObj(entry)
        unregisterTwObj(scr, entry)
        result === nothing && return (nothing, false)
        return (result, true)
    end
end

function _dt_add_to_dict!(o::TwObj{TwDictTreeData}, target::AbstractDict, target_path)
    scr = o.screen.value

    # Step 1 — key name
    ke = newTwEntry(scr, String; width = 32, posy = :center, posx = :center,
                    title = "New key: ", box = true)
    key_str = activateTwObj(ke)
    unregisterTwObj(scr, ke)
    key_str === nothing && return false
    key_str = strip(key_str)
    isempty(key_str) && return false

    KT  = keytype(target)
    local new_key
    if KT == Symbol
        new_key = Symbol(key_str)
    elseif KT <: Integer
        v = tryparse(KT, key_str)
        v === nothing && (beep(); return false)
        new_key = v
    else
        new_key = key_str
    end
    haskey(target, new_key) && (beep(); return false)

    # Step 2 — value type
    vtype = _dt_ask_type!(scr)
    vtype === nothing && return false

    # Step 3 — initial value
    (new_val, ok) = _dt_ask_value!(scr, vtype)
    !ok && return false

    target[new_key] = new_val
    o.data.openstatemap[target_path] = true   # ensure parent is expanded
    _dt_update_data!(o)
    _dt_find_and_goto!(o, vcat(target_path, [new_key]))
    _dt_snapshot!(o)
    return true
end

function _dt_add_to_vector!(o::TwObj{TwDictTreeData}, target::AbstractVector, target_path)
    scr = o.screen.value

    # Determine element type
    ET = eltype(target)
    local vtype
    if ET == Any
        vtype = _dt_ask_type!(scr)
        vtype === nothing && return false
    else
        vtype = ET
    end

    (new_val, ok) = _dt_ask_value!(scr, vtype)
    !ok && return false

    push!(target, new_val)
    new_idx = length(target)
    o.data.openstatemap[target_path] = true
    _dt_update_data!(o)
    _dt_find_and_goto!(o, vcat(target_path, [new_idx]))
    _dt_snapshot!(o)
    return true
end

function _dt_add_entry!(o::TwObj{TwDictTreeData})
    data  = o.data
    row   = data.datalist[data.currentLine]
    stack = row.stack

    val_at_cursor = getvaluebypath(o.value, copy(stack))
    if isa(val_at_cursor, AbstractDict)
        return _dt_add_to_dict!(o, val_at_cursor, stack)
    elseif isa(val_at_cursor, AbstractVector)
        return _dt_add_to_vector!(o, val_at_cursor, stack)
    elseif !isempty(stack)
        parent = getvaluebypath(o.value, copy(stack[1:end-1]))
        parent_path = stack[1:end-1]
        if isa(parent, AbstractDict)
            return _dt_add_to_dict!(o, parent, parent_path)
        elseif isa(parent, AbstractVector)
            return _dt_add_to_vector!(o, parent, parent_path)
        end
    end
    beep()
    return false
end

function _dt_delete_entry!(o::TwObj{TwDictTreeData})
    data  = o.data
    scr   = o.screen.value
    row   = data.datalist[data.currentLine]
    stack = row.stack
    isempty(stack) && (beep(); return false)

    val = getvaluebypath(o.value, copy(stack))

    # Confirm if deleting a non-empty container
    needs_confirm = (isa(val, AbstractDict) || isa(val, AbstractVector)) && !isempty(val)
    if needs_confirm
        n    = length(val)
        name = row.name
        popup = newTwPopup(
            scr, ["No", "Yes"];
            posy = :center, posx = :center,
            title = "Delete '$name' ($n children)?",
            maxwidth = 44,
            colorpair = 12 #red chicken box
        )
        choice = activateTwObj(popup)
        unregisterTwObj(scr, popup)
        choice != "Yes" && return false
    end

    ok = _dt_delete_at_path!(o.value, stack)
    ok || (beep(); return false)
    _dt_update_data!(o)
    data.currentLine = max(1, min(data.currentLine, data.datalistlen))
    _dt_checkTop!(o)
    _dt_snapshot!(o)
    return true
end

function _dt_rename_key!(o::TwObj{TwDictTreeData})
    data  = o.data
    scr   = o.screen.value
    row   = data.datalist[data.currentLine]
    stack = row.stack
    isempty(stack) && (beep(); return false)

    parent = getvaluebypath(o.value, copy(stack[1:end-1]))
    isa(parent, AbstractDict) || (beep(); return false)

    old_key = stack[end]
    isa(old_key, Integer) && (beep(); return false)   # Vector indices cannot be renamed

    ke = newTwEntry(scr, String; width = 32, posy = :center, posx = :center,
                    title = "Rename key: ", box = true)
    ke.data.inputText = string(old_key)
    ke.data.cursorPos = length(ke.data.inputText) + 1
    new_key_str = activateTwObj(ke)
    unregisterTwObj(scr, ke)
    new_key_str === nothing && return false
    new_key_str = strip(new_key_str)
    isempty(new_key_str) && return false

    KT = keytype(parent)
    new_key = KT == Symbol ? Symbol(new_key_str) : new_key_str
    new_key == old_key && return false
    haskey(parent, new_key) && (beep(); return false)

    val = parent[old_key]
    delete!(parent, old_key)
    parent[new_key] = val

    _dt_update_data!(o)
    new_stack = vcat(stack[1:end-1], [new_key])
    _dt_find_and_goto!(o, new_stack)
    _dt_snapshot!(o)
    return true
end

function _dt_swap_vector_element!(o::TwObj{TwDictTreeData}, direction::Int)
    data  = o.data
    row   = data.datalist[data.currentLine]
    stack = row.stack
    isempty(stack) && (beep(); return false)

    parent  = getvaluebypath(o.value, copy(stack[1:end-1]))
    old_idx = stack[end]
    (isa(parent, AbstractVector) && isa(old_idx, Integer)) || (beep(); return false)

    new_idx = old_idx + direction
    (new_idx < 1 || new_idx > length(parent)) && (beep(); return false)

    parent[old_idx], parent[new_idx] = parent[new_idx], parent[old_idx]
    _dt_update_data!(o)
    new_stack = vcat(stack[1:end-1], [new_idx])
    _dt_find_and_goto!(o, new_stack)
    _dt_snapshot!(o)
    return true
end

# ─── nav helpers ─────────────────────────────────────────────────────────────

function _dt_moveby!(o::TwObj{TwDictTreeData}, n::Int)
    old = o.data.currentLine
    o.data.currentLine = max(1, min(o.data.datalistlen, o.data.currentLine + n))
    if old != o.data.currentLine
        _dt_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _dt_search_next!(o::TwObj{TwDictTreeData}, step::Int, trivialstop::Bool)
    data = o.data
    data.datalistlen == 0 && return 0
    (vh, _, _) = _dt_view_dims(o)
    st = data.currentLine
    data.searchText = lowercase(data.searchText)
    i = trivialstop ? st : (mod(st - 1 + step, data.datalistlen) + 1)
    while true
        if occursin(data.searchText, lowercase(data.datalist[i].name)) ||
           occursin(data.searchText, lowercase(data.datalist[i].valuestr))
            data.currentLine = i
            abs(i - st) > vh && (data.currentTop = data.currentLine - (vh >> 1))
            _dt_checkTop!(o)
            return i
        end
        i = mod(i - 1 + step, data.datalistlen) + 1
        i == st && (beep(); return 0)
    end
end

function _dt_expand_all!(o::TwObj{TwDictTreeData})
    data = o.data
    (vh, _, _) = _dt_view_dims(o)
    currentstack = data.datalist[data.currentLine].stack
    somethingchanged = false
    for i = 1:data.datalistlen
        if data.datalist[i].expandhint != :single
            stck = data.datalist[i].stack
            if !get(data.openstatemap, stck, false)
                data.openstatemap[stck] = true
                somethingchanged = true
            end
        end
    end
    if somethingchanged
        prevline = data.currentLine
        _dt_update_data!(o)
        for i = data.currentLine:data.datalistlen
            if currentstack == data.datalist[i].stack
                data.currentLine = i
                abs(i - prevline) > vh && (data.currentTop = i - round(Int, vh / 2))
                break
            end
        end
        _dt_checkTop!(o)
        return true
    else
        beep()
        return false
    end
end

function _dt_collapse_deepest!(o::TwObj{TwDictTreeData})
    data = o.data
    (vh, _, _) = _dt_view_dims(o)
    data.datalistlen == 0 && (beep(); return)
    currentstack = copy(data.datalist[data.currentLine].stack)
    maxdepth = maximum(map(x -> length(x.stack), data.datalist))
    maxdepth <= 1 && (beep(); return)
    somethingchanged = false
    for i = 1:data.datalistlen
        stck = data.datalist[i].stack
        if data.datalist[i].expandhint != :single && length(stck) == maxdepth - 1
            if get(data.openstatemap, stck, false)
                data.openstatemap[stck] = false
                somethingchanged = true
            end
        end
    end
    if somethingchanged
        _dt_update_data!(o)
        length(currentstack) == maxdepth && pop!(currentstack)
        prevline = data.currentLine; data.currentLine = 1
        for i = 1:min(prevline, data.datalistlen)
            if currentstack == data.datalist[i].stack
                data.currentLine = i
                abs(i - prevline) > vh && (data.currentTop = i - round(Int, vh / 2))
                break
            end
        end
        _dt_checkTop!(o)
    else
        beep()
    end
end

function _dt_collapse_all!(o::TwObj{TwDictTreeData})
    data = o.data
    (vh, _, _) = _dt_view_dims(o)
    data.datalistlen == 0 && return
    currentstack = copy(data.datalist[data.currentLine].stack)
    length(currentstack) > 1 && (currentstack = Any[currentstack[1]])
    data.openstatemap = Dict{Any,Bool}()
    data.openstatemap[Any[]] = true
    _dt_update_data!(o)
    prevline = data.currentLine; data.currentLine = 1
    for i = 1:min(prevline, data.datalistlen)
        if currentstack == data.datalist[i].stack
            data.currentLine = i
            abs(i - prevline) > vh && (data.currentTop = data.currentLine - round(Int, vh / 2))
            break
        end
    end
    _dt_checkTop!(o)
end

# ─── draw ─────────────────────────────────────────────────────────────────────

function _dt_draw_edit_cell!(
    o::TwObj{TwDictTreeData},
    y::Int,
    startx::Int,
    fieldW::Int,
)
    # The active leaf is rendered by the shared InlineEditor renderer. Editing is
    # always focused, and the dict tree shows the incomplete color even while
    # focused (incomplete_priority), unlike entry/edittable.
    o.data.editor.width = fieldW
    draw_editor!(o.window, y, startx, o.data.editor, true; incomplete_priority = true)
end

function draw(o::TwObj{TwDictTreeData})
    _dt_update_dimensions!(o)
    data = o.data
    (viewH, viewW, fieldW) = _dt_view_dims(o)

    if o.box
        if o.borderAttr !== nothing
            box_colored(o.window, 0, 0, o.borderAttr.channels)
            wattron(o.window, o.borderAttr)
        else
            box(o.window, 0, 0)
        end
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, max(0, round(Int, (o.width - length(o.title)) / 2)), "%s", o.title)
        if o.borderAttr !== nothing
            wattroff(o.window, o.borderAttr)
        end
    end
    if data.showLineInfo && o.box && data.datalistlen > 0
        msg = data.datalistlen <= viewH ? "ALL" :
            @sprintf("%d/%d %5.1f%%", data.currentLine, data.datalistlen,
                     data.currentLine / data.datalistlen * 100)
        mvwprintw(o.window, 0, max(0, o.width - length(msg) - 3), "%s", msg)
    end

    for r = data.currentTop:min(data.currentTop + viewH - 1, data.datalistlen)
        stacklen   = length(data.datalist[r].stack)
        expandhint = data.datalist[r].expandhint

        s = ensure_length(
            repeat(" ", 2 * stacklen + 1) * data.datalist[r].name,
            data.datatreewidth,
        )
        t = ensure_length(data.datalist[r].typestr, data.datatypewidth)
        v = ensure_length(
            data.datalist[r].valuestr,
            viewW - data.datatreewidth - data.datatypewidth - 3,
            false,
        )

        is_current = (r == data.currentLine)
        if is_current
            wattron(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
        end

        y = 1 + r - data.currentTop
        mvwprintw(o.window, y, 2, "%s", s)
        mvwaddch(o.window, y, 2 + data.datatreewidth, get_acs_val('x'))
        mvwprintw(o.window, y, 2 + data.datatreewidth + 1, "%s", t)
        mvwaddch(o.window, y, 2 + data.datatreewidth + data.datatypewidth + 1, get_acs_val('x'))

        value_startx = 2 + data.datatreewidth + data.datatypewidth + 2
        if is_current && data.isEditing
            if is_current
                wattroff(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
            end
            _dt_draw_edit_cell!(o, y, value_startx, fieldW)
        else
            mvwprintw(o.window, y, value_startx, "%s", v)
            if is_current
                wattroff(o.window, A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused))
            end
        end

        # tree connectors
        for i = 1:(stacklen - 1)
            if !in(i, data.datalist[r].skiplines)
                mvwaddch(o.window, y, 2 * i, get_acs_val('x'))
            end
        end
        if stacklen != 0
            contchar = get_acs_val('t')
            if r == data.datalistlen ||
               length(data.datalist[r + 1].stack) < stacklen ||
               (length(data.datalist[r + 1].stack) > stacklen &&
                in(stacklen, data.datalist[r + 1].skiplines))
                contchar = get_acs_val('m')
            end
            mvwaddch(o.window, y, 2 * stacklen, contchar)
            mvwaddch(o.window, y, 2 * stacklen + 1, get_acs_val('q'))
        end
        if expandhint == :close
            mvwprintw(o.window, y, 2 * stacklen + 2, "%s", string(Char(0x25b8)))
        elseif expandhint == :open
            mvwprintw(o.window, y, 2 * stacklen + 2, "%s", string(Char(0x25be)))
        end
    end

    if !isempty(data.bottomText) && o.box
        mvwprintw(o.window, o.height - 1,
                  max(0, round(Int, (o.width - length(data.bottomText)) / 2)),
                  "%s", data.bottomText)
    end
end

# ─── bindings + inject ────────────────────────────────────────────────────────

function bindings(o::TwObj{TwDictTreeData})
    vh = () -> o.height - 2 * o.borderSizeV
    [
        Binding(:esc,  "cancel", action = _->Cancel),
        Binding(:F10,  "submit", action = _->Accept),
        Binding(" ", "toggle expand",
                action = _->begin
                    stck = o.data.datalist[o.data.currentLine].stack
                    val  = getvaluebypath(o.value, copy(stck))
                    if isa(val, AbstractDict) || isa(val, AbstractVector)
                        o.data.openstatemap[stck] = !get(o.data.openstatemap, stck, false)
                        _dt_update_data!(o)
                    else
                        beep()
                    end
                    Handled
                end),
        Binding([:enter, Symbol("return"), "e", :F2], "expand / edit",
                action = _->begin
                    stck = o.data.datalist[o.data.currentLine].stack
                    val  = getvaluebypath(o.value, copy(stck))
                    if isa(val, AbstractDict) || isa(val, AbstractVector)
                        o.data.openstatemap[stck] = !get(o.data.openstatemap, stck, false)
                        _dt_update_data!(o)
                    else
                        _dt_begin_edit!(o) || beep()
                    end
                    Handled
                end),
        Binding(:ctrl_n, "add entry",   action = _->(_dt_add_entry!(o); Handled)),
        Binding(:ctrl_d, "delete",      action = _->(_dt_delete_entry!(o); Handled)),
        Binding("r",     "rename key",  action = _->(_dt_rename_key!(o); Handled)),
        Binding(:alt_up,   "move up",   action = _->(_dt_swap_vector_element!(o, -1); Handled)),
        Binding(:alt_down, "move down", action = _->(_dt_swap_vector_element!(o,  1); Handled)),
        Binding("+", "expand all",     action = _->(_dt_expand_all!(o); Handled)),
        Binding("-", "collapse level", action = _->(_dt_collapse_deepest!(o); Handled)),
        Binding("_", "collapse all",   action = _->(_dt_collapse_all!(o); Handled)),
        Binding(:F5, "show as string",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, copy(stck))
                    v isa Expr ? tshow(exprstring(v), "julia"; title = string(lastkey)) :
                                 tshow(string(v); title = string(lastkey))
                    Handled
                end),
        Binding(:F6, "popup value",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, stck)
                    !in(v, [nothing, Nothing, Any]) && tshow(v, title = string(lastkey))
                    Handled
                end),
        Binding(:F7, o.data.isScratchpad ? "export to Main" : "pin to scratchpad",
                action = _->begin
                    stck = copy(o.data.datalist[o.data.currentLine].stack)
                    lastkey = isempty(stck) ? o.title : stck[end]
                    v = getvaluebypath(o.value, stck)
                    if o.data.isScratchpad
                        name = string(lastkey)
                        try
                            export_to_main!(name)
                            tshow("Exported :$name to Main", title = "F7")
                        catch err
                            tshow("Error exporting variable:\n" * string(err), title = "F7 error")
                        end
                    else
                        helper = newTwEntry(o.screen.value, String;
                                           width = 34, posy = :center, posx = :center,
                                           title = "Pin to scratchpad as: ")
                        helper.data.inputText = string(lastkey)
                        helper.data.cursorPos = length(helper.data.inputText) + 1
                        varname = activateTwObj(helper)
                        unregisterTwObj(o.screen.value, helper)
                        if varname !== nothing && !isempty(strip(varname))
                            pin!(strip(varname), v)
                        end
                    end
                    Handled
                end),
        Binding(:up,   "up",   action = _->(_dt_moveby!(o, -1); Handled)),
        Binding(:down, "down", action = _->(_dt_moveby!(o,  1); Handled)),
        Binding(:ctrl_left, "parent",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :parent)
                    moved ? (o.data.currentLine = target; _dt_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_up, "prev sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :prev_sibling)
                    moved ? (o.data.currentLine = target; _dt_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:ctrl_down, "next sibling",
                action = _->begin
                    (target, moved) = tree_nav(o.data.datalist, o.data.currentLine, :next_sibling)
                    moved ? (o.data.currentLine = target; _dt_checkTop!(o)) : beep()
                    Handled
                end),
        Binding(:pageup,   "page up",   action = _->(_dt_moveby!(o, -vh()); Handled)),
        Binding(:pagedown, "page down", action = _->(_dt_moveby!(o,  vh()); Handled)),
        Binding(:home, "go to start",
                action = _->begin
                    if o.data.currentTop != 1 || o.data.currentLine != 1
                        o.data.currentTop = 1; o.data.currentLine = 1
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(Symbol("end"), "go to end",
                action = _->begin
                    if o.data.currentLine < o.data.datalistlen
                        o.data.currentLine = o.data.datalistlen; _dt_checkTop!(o)
                    else
                        beep()
                    end
                    Handled
                end),
        Binding("/", "search",
                action = _->begin
                    helper = newTwEntry(o.screen.value, String;
                                       width = 30, posy = :center, posx = :center,
                                       title = "Search: ")
                    helper.data.inputText = o.data.searchText
                    s = activateTwObj(helper)
                    unregisterTwObj(o.screen.value, helper)
                    if s !== nothing && s != "" && o.data.searchText != s
                        o.data.searchText = s
                        _dt_search_next!(o, 1, true)
                    end
                    Handled
                end),
        Binding(["n", "N"], "next match",
                action = _->(o.data.searchText != "" && o.data.datalistlen > 0 &&
                              _dt_search_next!(o,  1, false); Handled)),
        Binding(["p", :ctrl_p], "prev match",
                action = _->(o.data.searchText != "" && o.data.datalistlen > 0 &&
                              _dt_search_next!(o, -1, false); Handled)),
        Binding(:ctrl_z, "undo",
                when   = _-> can_undo(o.data.history),
                action = _-> begin
                    (prev, ok) = undo!(o.data.history)
                    if ok
                        o.value = deepcopy(prev)
                        _dt_update_data!(o)
                        o.data.currentLine = min(o.data.currentLine, max(1, o.data.datalistlen))
                        _dt_checkTop!(o)
                    else
                        beep()
                    end
                    Handled
                end),
        Binding(:ctrlshift_z, "redo",
                when   = _-> can_redo(o.data.history),
                action = _-> begin
                    (next_state, ok) = redo!(o.data.history)
                    if ok
                        o.value = deepcopy(next_state)
                        _dt_update_data!(o)
                        o.data.currentLine = min(o.data.currentLine, max(1, o.data.datalistlen))
                        _dt_checkTop!(o)
                    else
                        beep()
                    end
                    Handled
                end),
    ]
end

function _dt_sel_text(o::TwObj{TwDictTreeData})
    isempty(o.data.datalist) && return ""
    row = o.data.datalist[clamp(o.data.currentLine, 1, length(o.data.datalist))]
    "$(row.name) :: $(row.typestr)"
end

function inject(o::TwObj{TwDictTreeData}, token)
    data = o.data

    # 1. Edit mode pre-empts all tokens
    if data.isEditing
        (_, _, fieldW) = _dt_view_dims(o)
        ed = data.editor
        ed.width = fieldW

        if token == :esc
            data.isEditing = false
            ed.incomplete = false
        elseif token == :enter || token == Symbol("return")
            _dt_commit_edit!(o) || beep()
        else
            r = editor_handle(ed, token)
            if r === :handled
                # nothing extra
            elseif r === :rejected || r === :at_left_edge || r === :at_right_edge
                beep()
            elseif r === :open_calendar
                (parsed, _) = evalNFormat(ed, ed.buffer, fieldW)
                init_date = parsed isa Dates.Date ? parsed : Dates.today()
                cal = newTwCalendar(o.screen.value, init_date; posy = :center, posx = :center)
                activateTwObj(cal)
                cal.value isa Dates.Date &&
                    editor_set_buffer!(ed, Dates.format(cal.value, "yyyy-mm-dd"))
                unregisterTwObj(o.screen.value, cal)
            else
                return Ignored
            end
        end
        refresh(o)
        return Handled
    end

    # 2. Bindings table (nav + structural ops)
    r = inject_via_table(o, token)
    if r === Handled
        set!(o.data.selection_text, _dt_sel_text(o))
        refresh(o)
        return r
    end
    r !== Ignored && return r

    # 3. h-scroll and mouse (undocumented)
    (viewH, viewW, _) = _dt_view_dims(o)
    if token == :left
        data.currentLeft > 1 ? (data.currentLeft -= 1; refresh(o)) : beep()
        return Handled
    elseif token == :right
        data.currentLeft + o.width - 2 * o.borderSizeH < viewW ?
            (data.currentLeft += 1; refresh(o)) : beep()
        return Handled
    elseif token == :KEY_MOUSE
        (mstate, x, y, _) = getmouse()
        if mstate == :scroll_up
            _dt_moveby!(o, -(round(Int, viewH / 5))); refresh(o)
        elseif mstate == :scroll_down
            _dt_moveby!(o,  round(Int, viewH / 5));  refresh(o)
        elseif mstate == :button1_pressed
            rely, relx = screen_to_relative(o.window, y, x)
            if isa(o.window, TwWindow)
                rely -= o.window.yloc; relx -= o.window.xloc
            end
            if 0 <= relx < o.width && o.borderSizeV <= rely < o.height - o.borderSizeV
                clicked = data.currentTop + rely - o.borderSizeV
                if 1 <= clicked <= data.datalistlen
                    data.currentLine = clicked; _dt_checkTop!(o)
                    set!(o.data.selection_text, _dt_sel_text(o)); refresh(o)
                end
            else
                return Ignored
            end
        end
        return Handled
    end

    return Ignored
end

# ─── helptext ─────────────────────────────────────────────────────────────────

helptext(o::TwObj{TwDictTreeData}) = o.data.showHelp ? helptext_from_bindings(o) : ""

function clamp_scroll!(o::TwObj{TwDictTreeData})
    _dt_update_dimensions!(o)
    data = o.data
    vh = o.height - 2 * o.borderSizeV
    vh < 1 && return
    data.currentLine = clamp(data.currentLine, 1, max(1, data.datalistlen))
    data.currentTop  = clamp(data.currentTop,  1, max(1, data.datalistlen - vh + 1))
    data.currentTop  = min(data.currentTop, data.currentLine)
    if data.currentLine - data.currentTop > vh - 1
        data.currentTop = data.currentLine - vh + 1
    end
end
