# twdicttree.jl — editable tree viewer for Dict/Vector structures

defaultDictTreeHelpText = """
PgUp/PgDn,
Arrow keys : navigation
<spc>      : toggle expand/collapse
<rtn>      : expand/collapse (container) or edit (leaf)
e, F2      : edit current leaf value inline
Ctrl-N     : add entry (child if on container, sibling if on leaf)
Ctrl-D     : delete current entry
r          : rename current Dict key
Alt-Up/Dn  : move Vector element up / down
ctrl_left  : jump to parent node
ctrl_up    : jump to previous sibling
ctrl_down  : jump to next sibling
+, -       : expand/collapse one level
_          : collapse all
/          : search dialog
n, p       : next / previous match
F5         : show string(value) — with Julia syntax color if Expr
F6         : popup viewer for value
F7         : store value into a Main global variable
F10        : submit changes and return
Esc        : cancel edit / exit without saving
"""

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
    helpText::String
    searchText::String
    # inline edit state
    isEditing::Bool
    editor::InlineEditor    # the active leaf's inline editor (state + parse/format)
end

function newTwDictTree(
    scr::TwObj,
    ex::AbstractDict;
    height::Real  = 1.0,
    width::Real   = 1.0,
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
        showLineInfo, bottomText, showHelp, defaultDictTreeHelpText, "",
        false, InlineEditor(String; width = 1),
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

function _dt_update_data!(o::TwObj{TwDictTreeData})
    data = o.data
    data.datalist = TreeRow[]
    tree_data(o.value, o.title, data.datalist, data.openstatemap, Any[], Int[], true)
    _dt_update_dimensions!(o)
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
    return true
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
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, max(0, round(Int, (o.width - length(o.title)) / 2)), "%s", o.title)
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

# ─── inject ───────────────────────────────────────────────────────────────────

function inject(o::TwObj{TwDictTreeData}, token)
    data      = o.data
    dorefresh = false
    retcode   = Handled

    (viewH, viewW, fieldW) = _dt_view_dims(o)

    update_data = () -> begin
        data.datalist = TreeRow[]
        tree_data(o.value, o.title, data.datalist, data.openstatemap, Any[], Int[], true)
        _dt_update_dimensions!(o)
    end

    checkTop = () -> _dt_checkTop!(o)

    moveby = n -> begin
        old = data.currentLine
        data.currentLine = max(1, min(data.datalistlen, data.currentLine + n))
        if old != data.currentLine
            checkTop()
            return true
        else
            beep()
            return false
        end
    end

    searchNext = (step, trivialstop) -> begin
        data.datalistlen == 0 && return 0
        local st = data.currentLine
        data.searchText = lowercase(data.searchText)
        i = trivialstop ? st : (mod(st - 1 + step, data.datalistlen) + 1)
        while true
            if occursin(data.searchText, lowercase(data.datalist[i].name)) ||
               occursin(data.searchText, lowercase(data.datalist[i].valuestr))
                data.currentLine = i
                abs(i - st) > viewH && (data.currentTop = data.currentLine - (viewH >> 1))
                checkTop()
                return i
            end
            i = mod(i - 1 + step, data.datalistlen) + 1
            i == st && (beep(); return 0)
        end
    end

    # ── edit mode ─────────────────────────────────────────────────────────────
    if data.isEditing
        ed = data.editor
        ed.width = fieldW

        if token == :esc
            data.isEditing = false
            ed.incomplete = false
            dorefresh = true
        elseif token == :enter || token == Symbol("return")
            _dt_commit_edit!(o) || beep()
            dorefresh = true
        else
            # All editing keys delegate to the shared InlineEditor.
            r = editor_handle(ed, token)
            if r === :handled
                dorefresh = true
            elseif r === :rejected || r === :at_left_edge || r === :at_right_edge
                beep()                 # dict tree leaves have no columns; edges beep
            elseif r === :open_calendar
                (parsed, _) = evalNFormat(ed, ed.buffer, fieldW)
                init_date = parsed isa Dates.Date ? parsed : Dates.today()
                cal = newTwCalendar(o.screen.value, init_date; posy = :center, posx = :center)
                activateTwObj(cal)
                cal.value isa Dates.Date &&
                    editor_set_buffer!(ed, Dates.format(cal.value, "yyyy-mm-dd"))
                unregisterTwObj(o.screen.value, cal)
                dorefresh = true
            else  # :open_enum (no enums here) or :ignored
                retcode = Ignored
            end
        end

    # ── navigation / structural mode ──────────────────────────────────────────
    else
        if token == :esc
            retcode = Cancel

        elseif token == :F10
            retcode = Accept

        elseif token == " "
            expandhint = data.datalist[data.currentLine].expandhint
            stck = data.datalist[data.currentLine].stack
            val  = getvaluebypath(o.value, copy(stck))
            if isa(val, AbstractDict) || isa(val, AbstractVector)
                data.openstatemap[stck] = !get(data.openstatemap, stck, false)
                update_data()
                dorefresh = true
            else
                beep()
            end

        elseif token == :enter || token == Symbol("return") || token == "e" || token == :F2
            row        = data.datalist[data.currentLine]
            expandhint = row.expandhint
            stck       = row.stack
            val        = getvaluebypath(o.value, copy(stck))
            if isa(val, AbstractDict) || isa(val, AbstractVector)
                # toggle expand/collapse for containers
                data.openstatemap[stck] = !get(data.openstatemap, stck, false)
                update_data()
                dorefresh = true
            else
                if _dt_begin_edit!(o)
                    dorefresh = true
                else
                    beep()
                end
            end

        elseif token == :ctrl_n
            _dt_add_entry!(o)
            dorefresh = true

        elseif token == :ctrl_d
            _dt_delete_entry!(o)
            dorefresh = true

        elseif token == "r"
            _dt_rename_key!(o)
            dorefresh = true

        elseif token == :alt_up
            _dt_swap_vector_element!(o, -1)
            dorefresh = true

        elseif token == :alt_down
            _dt_swap_vector_element!(o, 1)
            dorefresh = true

        elseif token == "+"
            currentstack  = data.datalist[data.currentLine].stack
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
                update_data()
                for i = data.currentLine:data.datalistlen
                    if currentstack == data.datalist[i].stack
                        data.currentLine = i
                        abs(i - prevline) > viewH && (data.currentTop = i - round(Int, viewH / 2))
                        break
                    end
                end
                checkTop()
                dorefresh = true
            else
                beep()
            end

        elseif token == "-"
            currentstack  = copy(data.datalist[data.currentLine].stack)
            maxdepth = maximum(map(x -> length(x[4]), data.datalist))
            somethingchanged = false
            if maxdepth > 1
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
                    update_data()
                    length(currentstack) == maxdepth && pop!(currentstack)
                    prevline = data.currentLine; data.currentLine = 1
                    for i = 1:min(prevline, data.datalistlen)
                        if currentstack == data.datalist[i].stack
                            data.currentLine = i
                            abs(i - prevline) > viewH && (data.currentTop = i - round(Int, viewH / 2))
                            break
                        end
                    end
                    checkTop()
                    dorefresh = true
                end
            else
                beep()
            end

        elseif token == "_"
            currentstack = copy(data.datalist[data.currentLine].stack)
            length(currentstack) > 1 && (currentstack = Any[currentstack[1]])
            data.openstatemap = Dict{Any,Bool}()
            data.openstatemap[Any[]] = true
            update_data()
            prevline = data.currentLine; data.currentLine = 1
            for i = 1:min(prevline, data.datalistlen)
                if currentstack == data.datalist[i].stack
                    data.currentLine = i
                    abs(i - prevline) > viewH && (data.currentTop = data.currentLine - round(Int, viewH / 2))
                    break
                end
            end
            checkTop()
            dorefresh = true

        elseif token == :up
            dorefresh = moveby(-1)

        elseif token == :down
            dorefresh = moveby(1)

        elseif token == :pageup
            dorefresh = moveby(-viewH)

        elseif token == :pagedown
            dorefresh = moveby(viewH)

        elseif token == :home
            if data.currentTop != 1 || data.currentLine != 1
                data.currentTop = 1; data.currentLine = 1
                dorefresh = true
            else
                beep()
            end

        elseif in(token, Any[Symbol("end")])
            if data.currentLine < data.datalistlen
                data.currentLine = data.datalistlen
                checkTop()
                dorefresh = true
            else
                beep()
            end

        elseif token == :left
            if data.currentLeft > 1
                data.currentLeft -= 1; dorefresh = true
            else
                beep()
            end

        elseif token == :right
            if data.currentLeft + o.width - 2 * o.borderSizeH < viewW
                data.currentLeft += 1; dorefresh = true
            else
                beep()
            end

        elseif token == :ctrl_left || token == :ctrl_up || token == :ctrl_down
            # Parent / prev-sibling / next-sibling, shared with the tree and file
            # browser via the generic tree_nav primitive.
            dir = token == :ctrl_left ? :parent :
                  token == :ctrl_up   ? :prev_sibling : :next_sibling
            (target, moved) = tree_nav(data.datalist, data.currentLine, dir)
            if moved
                data.currentLine = target; checkTop(); dorefresh = true
            else
                beep()
            end

        elseif token == :F5
            stck = copy(data.datalist[data.currentLine].stack)
            lastkey = isempty(stck) ? o.title : stck[end]
            v = getvaluebypath(o.value, copy(stck))
            if v isa Expr
                tshow(exprstring( v ), "julia"; title = string(lastkey))
            else
                s = string(v)
                tshow(s; title = string(lastkey))
            end
            dorefresh = true

        elseif token == :F6
            stck = copy(data.datalist[data.currentLine].stack)
            lastkey = isempty(stck) ? o.title : stck[end]
            v = getvaluebypath(o.value, stck)
            if !in(v, [nothing, Nothing, Any])
                tshow(v, title = string(lastkey))
                dorefresh = true
            end

        elseif token == :F7
            stck = copy(data.datalist[data.currentLine].stack)
            lastkey = isempty(stck) ? o.title : stck[end]
            v = getvaluebypath(o.value, stck)
            helper = newTwEntry(
                o.screen.value,
                String;
                width = 34,
                posy = :center,
                posx = :center,
                title = "Store as global: ",
            )
            helper.data.inputText = string(lastkey)
            helper.data.cursorPos = length(helper.data.inputText) + 1
            varname = activateTwObj(helper)
            unregisterTwObj(o.screen.value, helper)
            if varname !== nothing && !isempty(strip(varname))
                try
                    Core.eval(Main, Expr(:(=), Symbol(strip(varname)), QuoteNode(v)))
                catch err
                    tshow("Error storing variable:\n" * string(err), title = "F7 error")
                end
            end
            dorefresh = true

        elseif token == "/"
            helper = newTwEntry(
                o.screen.value, String;
                width = 30, posy = :center, posx = :center, title = "Search: ",
            )
            helper.data.inputText = data.searchText
            s = activateTwObj(helper)
            unregisterTwObj(o.screen.value, helper)
            if s !== nothing && s != "" && data.searchText != s
                data.searchText = s
                searchNext(1, true)
            end
            dorefresh = true

        elseif token == "n" || token == "p" || token == "N" || token == :ctrl_p
            if data.searchText != "" && data.datalistlen > 0
                searchNext(((token == "n" || token == "N") ? 1 : -1), false)
            end
            dorefresh = true

        elseif token == :KEY_MOUSE
            (mstate, x, y, _) = getmouse()
            if mstate == :scroll_up
                dorefresh = moveby(-(round(Int, viewH / 5)))
            elseif mstate == :scroll_down
                dorefresh = moveby(round(Int, viewH / 5))
            elseif mstate == :button1_pressed
                begy, begx = getwinbegyx(o.window)
                relx = x - begx; rely = y - begy
                if 0 <= relx < o.width && 0 <= rely < o.height
                    clicked = data.currentTop + rely - o.borderSizeV
                    if 1 <= clicked <= data.datalistlen
                        data.currentLine = clicked; checkTop(); dorefresh = true
                    end
                else
                    retcode = Ignored
                end
            end

        else
            retcode = Ignored
        end
    end

    if dorefresh
        refresh(o)
    end
    retcode
end

# ─── helptext ─────────────────────────────────────────────────────────────────

function helptext(o::TwObj{TwDictTreeData})
    o.data.showHelp ? o.data.helpText : ""
end

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
