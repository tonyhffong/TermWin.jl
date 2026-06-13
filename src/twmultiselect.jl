# multi selection widget

SELECTEDORDERABLE = 1 # whether selected items are orderable, selected always on top
SELECTSUBSTR = 2 # search by substring (default by prefix)

const _MS_SEARCHBOX_HELP = """
Search box (always active):
Alt-Space      : insert space in search box
Ctrl-A         : search cursor to start
Ctrl-E         : search cursor to end
Ctrl-K         : clear search box
Ctrl-R         : toggle insert/overwrite
"""

mutable struct TwMultiSelectData
    choices::Array{String,1}
    selected::Array{String,1}
    datalist::Array{Any,1}
    maxchoicelength::Int
    searchbox::Any
    scroll::ScrollState      # cursor=current line, top=first visible, left=h-scroll
    selectmode::Int
    exit_disabled::Bool
    TwMultiSelectData(arr::Array{String,1}, selected::Array{String,1}) =
        new(arr, selected, Any[], 0, nothing, ScrollState(), 0, false)
end
TwMultiSelectData(
    arr::Array{T,1},
    selected::Array{T2,1},
) where {T<:AbstractString,T2<:AbstractString} =
    TwMultiSelectData(map(x->String(x), arr), map(x->String(x), selected))

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
function newTwMultiSelect(
    scr::TwObj,
    arr::Array{T,1};
    posy::Any = :center,
    posx::Any = :center,
    selected = String[],
    title = "",
    maxwidth = 50,
    maxheight = 20,
    minwidth = 25,
    orderable = false,
    substrsearch = false,
    key::Union{Nothing,Symbol} = nothing,
) where {T<:AbstractString}
    obj = TwObj(
        TwMultiSelectData(arr, String[string(x) for x in selected]),
        Val{:MultiSelect},
    )
    obj.box = true
    obj.title = title
    obj.borderSizeV = 1
    obj.borderSizeH = 1
    if orderable
        obj.data.selectmode |= SELECTEDORDERABLE
    end
    if substrsearch
        obj.data.selectmode |= SELECTSUBSTR
    end
    rebuild_select_datalist(obj)
    obj.data.maxchoicelength = 0
    if !isempty(arr)
        obj.data.maxchoicelength = maximum(map(x->length(x), arr))
    end

    h = 2 + min(length(arr), maxheight)
    # 2 borders, ->, checkbox, a space
    w = 5 + max(min(max(length(title), obj.data.maxchoicelength), maxwidth), minwidth)

    link_parent_child(scr, obj, h, w, posy, posx)
    obj.formkey = key

    if !isempty(obj.data.selected)
        obj.value = copy(obj.data.selected)
    end

    obj.data.searchbox =
        newTwEntry(obj, String, width = minwidth, posy = :bottom, posx = 1, box = false)
    obj.data.searchbox.title = "?"
    obj.data.searchbox.hasFocus = false
    obj
end

function apply_default!(obj::TwObj{TwMultiSelectData}, value::AbstractVector)
    obj.data.selected = String[string(v) for v in value]
    rebuild_select_datalist(obj)
    obj.value = copy(obj.data.selected)
end

function rebuild_select_datalist(o::TwObj{TwMultiSelectData})
    o.data.datalist = Any[]
    if o.data.selectmode & SELECTEDORDERABLE != 0
        for s in o.data.selected
            push!(o.data.datalist, [s, true])
        end
        for s in o.data.choices
            if !in(s, o.data.selected)
                push!(o.data.datalist, [s, false])
            end
        end
    else
        for s in o.data.choices
            push!(o.data.datalist, [s, in(s, o.data.selected)])
        end
    end
end

# Keep the cursor visible when the viewport changes (terminal resize). The
# framework's relayout! calls this; multiselect previously had no such handler.
clamp_scroll!(o::TwObj{TwMultiSelectData}) =
    clamp_view!(o.data.scroll, length(o.data.datalist), o.height - 2 * o.borderSizeV)

function draw(o::TwObj{TwMultiSelectData})
    werase(o.window)
    if o.box
        if o.borderAttr !== nothing
            box_colored(o.window, 0, 0, o.borderAttr.channels)
            wattron(o.window, o.borderAttr)
        else
            box(o.window, 0, 0)
        end
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title))/2), "%s", o.title)
        if o.borderAttr !== nothing
            wattroff(o.window, o.borderAttr)
        end
    end
    starty = o.borderSizeV
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth = o.width - o.borderSizeH * 2
    n = length(o.data.datalist)
    for r = o.data.scroll.top:min(o.data.scroll.top+viewContentHeight-1, n)
        flag = 0
        prefix = " "
        if r == o.data.scroll.cursor
            flag = A_BOLD | theme(o.hasFocus ? :selection_focused : :selection_unfocused)
            prefix = "→"
        end
        s = o.data.datalist[r][1]
        if o.data.datalist[r][2] #checked!
            s = prefix * "■ " * s
        else
            s = prefix * "□ " * s
        end
        s = substr_by_width(s, o.data.scroll.left-1, viewContentWidth)

        wattron(o.window, flag)
        mvwprintw(o.window, r - o.data.scroll.top + starty, o.borderSizeH, "%s", s)
        wattroff(o.window, flag)
    end
    draw(o.data.searchbox)
end

function select_search_next(o::TwObj{TwMultiSelectData}, step::Int, trivialstop::Bool)
    st = o.data.scroll.cursor
    tmpstr = lowercase(o.data.searchbox.data.inputText)
    if length(tmpstr) == 0
        TermWin.beep()
        return 0
    end

    n = length(o.data.datalist)

    local i::Int = trivialstop ? st : mod1(st+step, n)
    local usesubstr::Bool = o.data.selectmode & SELECTSUBSTR != 0
    while true
        if usesubstr
            if occursin(tmpstr, lowercase(o.data.datalist[i][1]))
                o.data.scroll.cursor = i
                return i
            end
        else
            if startswith(lowercase(o.data.datalist[i][1]), tmpstr)
                o.data.scroll.cursor = i
                return i
            end
        end
        i = mod1(i+step, n)
        if i == st
            TermWin.beep()
            return 0
        end
    end
end

_ms_vph(o::TwObj{TwMultiSelectData}) = o.height - 2 * o.borderSizeV

function _ms_toggle!(o::TwObj{TwMultiSelectData})
    cur = o.data.scroll.cursor
    currstr  = o.data.datalist[cur][1]
    currstatus = o.data.datalist[cur][2]
    if !currstatus
        push!(o.data.selected, currstr)
    else
        deleteat!(o.data.selected, findfirst(isequal(currstr), o.data.selected))
    end
    if o.data.selectmode & SELECTEDORDERABLE != 0
        rebuild_select_datalist(o)
    else
        o.data.datalist[cur][2] = !currstatus
    end
end

function _ms_reorder!(o::TwObj{TwMultiSelectData}, delta::Int)
    cur = o.data.scroll.cursor
    o.data.datalist[cur][2] || (beep(); return Handled)   # not selected → beep
    currstr = o.data.datalist[cur][1]
    idx = findfirst(isequal(currstr), o.data.selected)
    target = idx + delta
    (target < 1 || target > length(o.data.selected)) && (beep(); return Handled)
    o.data.selected[target], o.data.selected[idx] =
        o.data.selected[idx], o.data.selected[target]
    o.data.scroll.cursor += delta
    rebuild_select_datalist(o)
    clamp_view!(o.data.scroll, length(o.data.datalist), _ms_vph(o))
    Handled
end

function bindings(o::TwObj{TwMultiSelectData})
    vph = _ms_vph(o)
    n   = () -> length(o.data.datalist)
    [
        Binding(:up,       "up",
                action = _->(move_cursor!(o.data.scroll, -1, n(), vph); Handled)),
        Binding(:down,     "down",
                action = _->(move_cursor!(o.data.scroll,  1, n(), vph); Handled)),
        Binding(:pageup,   "page up",
                action = _->(page!(o.data.scroll, -1, n(), vph); Handled)),
        Binding(:pagedown, "page down",
                action = _->(page!(o.data.scroll,  1, n(), vph); Handled)),
        Binding(:home,     "top",
                action = _->(o.data.scroll.top = 1; o.data.scroll.cursor = 1; o.data.scroll.left = 1; Handled)),
        Binding(Symbol("end"), "bottom",
                action = _->(o.data.scroll.cursor = n(); clamp_view!(o.data.scroll, n(), vph); Handled)),
        Binding(" ",       "toggle",
                action = _->(_ms_toggle!(o); Handled)),
        Binding([:enter, Symbol("return")], "confirm",
                action = _->(o.value = copy(o.data.selected); Accept)),
        Binding(:ctrl_n,   "next match",
                action = _->(select_search_next(o, 1, false);  clamp_view!(o.data.scroll, n(), vph); Handled)),
        Binding(:ctrl_p,   "prev match",
                action = _->(select_search_next(o, -1, false); clamp_view!(o.data.scroll, n(), vph); Handled)),
        Binding(:shift_up,   "move up",
                when   = _-> o.data.selectmode & SELECTEDORDERABLE != 0,
                action = _-> _ms_reorder!(o, -1)),
        Binding(:shift_down, "move down",
                when   = _-> o.data.selectmode & SELECTEDORDERABLE != 0,
                action = _-> _ms_reorder!(o,  1)),
        Binding(:esc, "cancel",
                when   = _-> !o.data.exit_disabled,
                action = _-> Cancel),
    ]
end

function inject(o::TwObj{TwMultiSelectData}, token)
    # 1. Search box pre-empts most tokens (except F1 and regular space).
    #    A non-breaking space (U+00A0) is normalized to regular space for the searchbox.
    if token != :F1 && token != " "
        inputText = o.data.searchbox.data.inputText
        if token == " "  # non-breaking space → normalize for searchbox
            token = " "
        end
        result = inject(o.data.searchbox, token)
        if result == Handled
            if inputText != o.data.searchbox.data.inputText
                select_search_next(o, 1, true)
                clamp_view!(o.data.scroll, length(o.data.datalist), _ms_vph(o))
            end
            refresh(o)
            return result
        end
    end

    # 2. Bindings table (documented nav + mode-conditional reorder + esc/confirm)
    r = inject_via_table(o, token)
    r === Handled && refresh(o)
    r !== Ignored && return r

    # 3. Secondary nav: h-scroll (undocumented), mouse, focus_off
    vw = o.width - o.borderSizeH * 2
    if token == :left || token == :shift_left
        if o.data.scroll.left > 1
            o.data.scroll.left -= 1; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :right || token == :shift_right
        if o.data.scroll.left + vw < o.data.maxchoicelength
            o.data.scroll.left += 1; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :ctrlshift_left
        if o.data.scroll.left > 1
            o.data.scroll.left = 1; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :ctrlshift_right
        if o.data.scroll.left + vw < o.data.maxchoicelength
            o.data.scroll.left = o.data.maxchoicelength - vw; refresh(o)
        else
            beep()
        end
        return Handled
    elseif token == :KEY_MOUSE
        (mstate, x, y, bs) = getmouse()
        vph = _ms_vph(o)
        if mstate == :scroll_up
            move_cursor!(o.data.scroll, -(round(Int, vph/10)), length(o.data.datalist), vph)
            refresh(o)
        elseif mstate == :scroll_down
            move_cursor!(o.data.scroll, round(Int, vph/10), length(o.data.datalist), vph)
            refresh(o)
        elseif mstate == :button1_pressed && o.data.trackLine
            (rely, relx) = screen_to_relative(o.window, y, x)
            if 0 <= relx < o.width && 0 <= rely < o.height
                o.data.scroll.cursor = o.data.scroll.top + rely - o.borderSizeH + 1
                refresh(o)
            else
                return Ignored
            end
        end
        return Handled
    elseif token == :focus_off
        o.value = copy(o.data.selected)
        return Handled
    end

    return Ignored
end

helptext(o::TwObj{TwMultiSelectData}) = helptext_from_bindings(o) * _MS_SEARCHBOX_HELP
