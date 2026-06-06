# popup selection widget
# default behavior is a simple scrollable box of strings that is selectable
# quickselect enable a searchbox. Users can type in a string and the cursor will jump to the first item matching
# that as a prefix

# Additional modification of the behavior:
# if substr is enabled, it'd search for any substr instead of a faster startswith
# if hideunmatched is enabled, any choice that doesn't match will be hidden. deleting the search string will revert
# if sortmatched is enabled (usually in conjunction with substr and but not hideunmatched), a levenstein distance
#  score will be generated and the result sorted according to the match score
# if allownew is enabled, the search box is also an entry box to enter new text, as long as there is no match.
#   Use trailing space to disambiguate. They will be stripped afterwards.

# But if no additional modification is used, tab-completion is enabled.

POPUPQUICKSELECT = 1
POPUPSUBSTR = 2
POPUPHIDEUNMATCHED = 4
POPUPSORTMATCHED = 8
POPUPALLOWNEW = 16

mutable struct TwPopupData
    choices::Array{String,1}
    datalist::Array{Any,1}
    maxchoicelength::Int
    searchbox::Any
    scroll::ScrollState      # cursor=selected line, top=first visible, left=h-scroll (1-based)
    selectmode::Int
    colorpair::Int
    TwPopupData(arr::Array{String,1}) =
        new(arr, Any[], maximum(map(z->length(z), arr)), nothing, ScrollState(), 0, 0)
end
TwPopupData(arr::Array{T,1}) where {T<:AbstractString} = TwPopupData(map(x->String(x), arr))

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left
function newTwPopup(
    scr::TwObj,
    arr::Array{Symbol,1};
    posy::Any = :center,
    posx::Any = :center,
    title = "",
    maxwidth = 50,
    maxheight = 15,
    minwidth = 20,
    quickselect = false,
    substrsearch = false,
    hideunmatched = false,
    sortmatched = false,
    allownew = false,
    key::Union{Nothing,Symbol} = nothing,
    colorpair::Int = 0,
)

    return (newTwPopup(
        scr,
        map(x->string(x), arr),
        posy = posy,
        posx = posx,
        title = title,
        maxwidth = maxwidth,
        maxheight = maxheight,
        minwidth = minwidth,
        quickselect = quickselect,
        substrsearch = substrsearch,
        hideunmatched = hideunmatched,
        sortmatched = sortmatched,
        allownew = allownew,
        key = key,
        colorpair = colorpair,
    ))
end

function newTwPopup(
    scr::TwObj,
    arr::Array{T,1};
    posy::Any = :center,
    posx::Any = :center,
    title = "",
    maxwidth = 50,
    maxheight = 15,
    minwidth = 20,
    quickselect = false,
    substrsearch = false,
    hideunmatched = false,
    sortmatched = false,
    allownew = false,
    key::Union{Nothing,Symbol} = nothing,
    colorpair::Int = 0,
) where {T<:AbstractString}
    obj = TwObj(TwPopupData(arr), Val{:Popup})
    obj.box = true
    obj.title = title
    obj.borderSizeV = 1
    obj.borderSizeH = 1
    if quickselect
        obj.data.selectmode |= POPUPQUICKSELECT
    end
    if substrsearch
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPSUBSTR
    end
    if hideunmatched
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPHIDEUNMATCHED
    end
    if sortmatched
        obj.data.selectmode |= POPUPQUICKSELECT | POPUPSUBSTR | POPUPSORTMATCHED
    end
    if allownew
        obj.data.selectmode |=
            POPUPQUICKSELECT | POPUPSUBSTR | POPUPHIDEUNMATCHED | POPUPALLOWNEW
    end
    usedatalist = popup_use_datalist(obj)
    if usedatalist
        rebuild_popup_datalist(obj)
    end
    obj.data.colorpair = colorpair

    h = 2 + min(length(arr), maxheight)
    # we add an extra 1 char for the →
    w = 3 + max(min(max(length(title), obj.data.maxchoicelength), maxwidth), minwidth)

    link_parent_child(scr, obj, h, w, posy, posx)
    obj.formkey = key

    obj.data.searchbox =
        newTwEntry(obj, String; width = minwidth, posy = :bottom, posx = 1, box = false)
    obj.data.searchbox.title = "?"
    obj.data.searchbox.hasFocus = false # so it looks dimmer than main cursor
    obj
end

function apply_default!(obj::TwObj{TwPopupData}, value)
    value === nothing && return
    if value isa Integer
        obj.data.scroll.cursor = clamp(Int(value), 1, length(obj.data.choices))
    else
        idx = findfirst(==(string(value)), obj.data.choices)
        idx !== nothing && (obj.data.scroll.cursor = idx)
    end
    obj.value = obj.data.choices[obj.data.scroll.cursor]
end

function popup_use_datalist(o::TwObj)
    o.data.selectmode & POPUPHIDEUNMATCHED != 0 || o.data.selectmode & POPUPSORTMATCHED != 0
end

# Number of rows currently navigable (datalist when filtering/sorting, else choices).
popup_count(o::TwObj{TwPopupData}) =
    popup_use_datalist(o) ? length(o.data.datalist) : length(o.data.choices)

# Visible row count inside the box.
popup_viewport(o::TwObj{TwPopupData}) = o.height - 2 * o.borderSizeV

# Keep the cursor visible when the viewport changes (e.g. terminal resize). The
# framework's relayout! calls this; popup previously had no such handler.
clamp_scroll!(o::TwObj{TwPopupData}) =
    clamp_view!(o.data.scroll, popup_count(o), popup_viewport(o))

function rebuild_popup_datalist(o::TwObj{TwPopupData})
    o.data.datalist = Any[]
    for (i, c) in enumerate(o.data.choices)
        searchstring = c
        push!(o.data.datalist, Any[lowercase(searchstring), c, i, 0.0])
    end
end

function draw(o::TwObj{TwPopupData})
    werase(o.window)
    use_theme = o.data.colorpair != 0
    base_attr = COLOR_PAIR( use_theme ? o.data.colorpair : 0 )
    # Semantic tokens replace the old magic numbers (15 = focused, 30 = unfocused).
    sel_pair  = use_theme ? COLOR_PAIR(o.data.colorpair) :
                            theme(o.hasFocus ? :selection_focused : :selection_unfocused)
    wattron( o.window, base_attr )
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && o.box
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title))/2), "%s", o.title)
    end
    starty = o.borderSizeV
    viewContentHeight = o.height - o.borderSizeV * 2
    viewContentWidth = o.width - o.borderSizeH * 2
    usedatalist = popup_use_datalist(o)
    if usedatalist
        n = length(o.data.datalist)
    else
        n = length(o.data.choices)
    end
    for r = o.data.scroll.top:min(o.data.scroll.top+viewContentHeight-1, n)
        if r == o.data.scroll.cursor
            flag = A_BOLD | sel_pair
            prefix = "→"
        else
            flag = base_attr
            prefix = " "
        end
        if usedatalist
            s = o.data.datalist[r][2]
        else
            s = o.data.choices[r]
        end
        s = prefix * substr_by_width(s, o.data.scroll.left - 1, viewContentWidth-1)
        sw = textwidth(s)
        if sw < viewContentWidth
            s = s * repeat(" ", viewContentWidth - sw)
        end
        wattron(o.window, flag)
        mvwprintw(o.window, r - o.data.scroll.top + starty, o.borderSizeH, "%s", s)
        wattroff(o.window, flag)
    end
    if o.data.selectmode & POPUPQUICKSELECT != 0
        draw(o.data.searchbox)
    end
end

function popup_search_next(o::TwObj{TwPopupData}, step::Int, trivialstop::Bool)
    st = o.data.scroll.cursor
    tmpstr = lowercase(o.data.searchbox.data.inputText)
    if length(tmpstr) == 0
        TermWin.beep()
        return 0
    end

    usedatalist = popup_use_datalist(o)
    if usedatalist
        n = length(o.data.datalist)
    else
        n = length(o.data.choices)
    end

    i = trivialstop ? st : (mod(st-1+step, n) + 1)
    while true
        if o.data.selectmode & POPUPSUBSTR != 0
            if usedatalist
                if occursin(tmpstr, o.data.datalist[i][1])
                    o.data.scroll.cursor = i
                    return i
                end
            else
                if occursin(tmpstr, lowercase(o.data.choices[i]))
                    o.data.scroll.cursor = i
                    return i
                end
            end
        else
            if startswith(lowercase(o.data.choices[i]), tmpstr)
                o.data.scroll.cursor = i
                return i
            end
        end
        i = mod(i-1+step, n) + 1
        if i == st
            TermWin.beep()
            return 0
        end
    end
end

function update_popup_score(o::TwObj{TwPopupData})
    searchterm = o.data.searchbox.data.inputText
    needx = o.data.maxchoicelength

    l1 = length(searchterm)
    usedatalist = popup_use_datalist(o)

    if usedatalist
        prevchoice = ""
        if length(o.data.datalist) >= o.data.scroll.cursor >= 1
            prevchoice = o.data.datalist[o.data.scroll.cursor][2]
        else
            o.data.scroll.cursor = 1
        end
        if l1 == 0
            rebuild_popup_datalist(o)
            for (i, row) in enumerate(o.data.datalist)
                if row[2] == prevchoice
                    o.data.scroll.cursor = i
                end
            end
        else
            if o.data.selectmode & POPUPHIDEUNMATCHED != 0
                o.data.datalist = Any[]
                if o.data.selectmode & POPUPSUBSTR != 0
                    for (i, c) in enumerate(o.data.choices)
                        if occursin(lowercase(searchterm), lowercase(c))
                            r = findfirst(lowercase(searchterm), lowercase(c))
                            startpos = r !== nothing ? first(r) : needx
                            push!(
                                o.data.datalist,
                                Any[lowercase(c), c, i, startpos+length(c)/needx],
                            )
                        end
                    end
                else
                    for (i, c) in enumerate(o.data.choices)
                        if startswith(lowercase(c), lowercase(searchterm))
                            push!(o.data.datalist, Any[lowercase(c), c, i, length(c)])
                        end
                    end
                end
                if o.data.selectmode & POPUPSORTMATCHED != 0
                    sort!(o.data.datalist, lt = (x, y)->x[4] < y[4])
                    for (i, row) in o.data.datalist
                        if prevchoice == row[2]
                            o.data.scroll.cursor = i
                        end
                    end
                end
            else # show everything
                # sort
                if o.data.selectmode & POPUPSORTMATCHED != 0
                    if o.data.selectmode & POPUPSUBSTR != 0
                        for row in o.data.datalist
                            ld = levenstein_distance(lowercase(searchterm), row[1])
                            l2 = length(row[1])
                            minld = abs(l1 - l2)
                            maxld = max(l1, l2)
                            # ld closer to the theoretical minimum should be deemed almost as good as a full match
			    normld = (ld - minld + 1) / (maxld - ld + 0.001 ) * l2
                            # finding the search term in the later part of a string should have a small penalty
                            substrpenalty = needx
                            r = findfirst(searchterm, row[1])
                            if r !== nothing
                                substrpenalty = first(r)
                            end
                            row[4] = ld + normld * 2 + substrpenalty * 0.1
                        end
                        # prefix-based
                    else
                        for row in o.data.datalist
                            if startswith(row[1], lowercase(searchterm))
                                row[4] = length(row[1])
                            else
                                row[4] = length(row[1]) + needx
                            end
                        end
                    end
                    sort!(o.data.datalist, lt = (x, y)->x[4] < y[4])
                    o.data.scroll.cursor = 1
                    o.data.scroll.top = 1
                else # don't sort, but jump to the next match one
                    popup_search_next(o, 1, true)
                end
            end
        end
    else # just jump to the first term with the matched
        popup_search_next(o, 1, true)
    end
end

const _POPUP_SEARCHBOX_HELP = """
Search box (always active):
Ctrl-A/Ctrl-E  : search cursor to start/end
Ctrl-K         : clear search box
Ctrl-R         : toggle insert/overwrite
"""

function bindings(o::TwObj{TwPopupData})
    vph = () -> popup_viewport(o)
    n   = () -> popup_count(o)
    [
        Binding(:esc, "cancel", action = _->Cancel),
        Binding(:up,       "up",        action = _->(move_cursor!(o.data.scroll, -1, n(), vph()); Handled)),
        Binding(:down,     "down",      action = _->(move_cursor!(o.data.scroll,  1, n(), vph()); Handled)),
        Binding(:pageup,   "page up",   action = _->(page!(o.data.scroll, -1, n(), vph()); Handled)),
        Binding(:pagedown, "page down", action = _->(page!(o.data.scroll,  1, n(), vph()); Handled)),
        Binding(:home, "go to top",
                action = _->begin
                    if o.data.scroll.top == 1 && o.data.scroll.left == 1 && o.data.scroll.cursor == 1
                        beep(); return Handled
                    end
                    o.data.scroll.top = 1; o.data.scroll.left = 1; o.data.scroll.cursor = 1
                    Handled
                end),
        Binding(Symbol("end"), "go to bottom",
                action = _->begin
                    if o.data.scroll.cursor == n()
                        beep(); return Handled
                    end
                    o.data.scroll.cursor = n()
                    clamp_view!(o.data.scroll, n(), vph())
                    Handled
                end),
        Binding([:enter, Symbol("return")], "select",
                action = _->begin
                    udl = popup_use_datalist(o)
                    if udl
                        if o.data.scroll.cursor <= length(o.data.datalist)
                            o.value = o.data.datalist[o.data.scroll.cursor][2]
                            return Accept
                        elseif o.data.selectmode & POPUPALLOWNEW != 0
                            o.value = strip(o.data.searchbox.data.inputText)
                            return Accept
                        end
                    else
                        if o.data.scroll.cursor <= length(o.data.choices)
                            o.value = o.data.choices[o.data.scroll.cursor]
                            return Accept
                        end
                    end
                    Handled
                end),
        Binding(:ctrl_n, "next match",
                when   = _-> o.data.selectmode & POPUPQUICKSELECT != 0,
                action = _->begin
                    popup_search_next(o, 1, false)
                    clamp_view!(o.data.scroll, n(), vph())
                    Handled
                end),
        Binding(:ctrl_p, "prev match",
                when   = _-> o.data.selectmode & POPUPQUICKSELECT != 0,
                action = _->begin
                    popup_search_next(o, -1, false)
                    clamp_view!(o.data.scroll, n(), vph())
                    Handled
                end),
        Binding(:tab, "tab-complete",
                when   = _-> (o.data.selectmode & POPUPQUICKSELECT != 0) &&
                             (o.data.selectmode & POPUPSUBSTR == 0),
                action = _->begin
                    udl = popup_use_datalist(o)
                    nextstr = ""; currstr = ""
                    if udl
                        if o.data.scroll.cursor < length(o.data.datalist)
                            currstr = o.data.datalist[o.data.scroll.cursor][2]
                            nextstr = o.data.datalist[o.data.scroll.cursor+1][2]
                        end
                    else
                        if o.data.scroll.cursor < length(o.data.choices)
                            currstr = o.data.choices[o.data.scroll.cursor]
                            nextstr = o.data.choices[o.data.scroll.cursor+1]
                        end
                    end
                    lcp = longest_common_prefix(currstr, nextstr)
                    if startswith(lcp, o.data.searchbox.data.inputText)
                        o.data.searchbox.data.inputText = lcp
                        inject(o.data.searchbox, :ctrl_e)
                    else
                        beep()
                    end
                    Handled
                end),
    ]
end

function inject(o::TwObj{TwPopupData}, token)
    viewContentWidth = o.width - o.borderSizeH * 2

    # Quickselect pre-emption: searchbox gets most tokens first (same pattern as multiselect).
    if o.data.selectmode & POPUPQUICKSELECT != 0 && token != :F1
        inputText = o.data.searchbox.data.inputText
        result = inject(o.data.searchbox, token)
        if result == Handled
            if inputText != o.data.searchbox.data.inputText
                update_popup_score(o)
                clamp_view!(o.data.scroll, popup_count(o), popup_viewport(o))
            end
            refresh(o)
            return result
        end
    end

    # Bindings table (nav, select, search-nav, tab-complete)
    r = inject_via_table(o, token)
    r === Handled && refresh(o)
    r !== Ignored && return r

    # h-scroll and mouse (undocumented, stay as fallthrough)
    if token in (:left, :shift_left)
        o.data.scroll.left > 1 ? (o.data.scroll.left -= 1; refresh(o)) : beep()
        return Handled
    elseif token in (:right, :shift_right)
        o.data.scroll.left + viewContentWidth < o.data.maxchoicelength ? (o.data.scroll.left += 1; refresh(o)) : beep()
        return Handled
    elseif token == :ctrlshift_left
        o.data.scroll.left > 1 ? (o.data.scroll.left = 1; refresh(o)) : beep()
        return Handled
    elseif token == :ctrlshift_right
        o.data.scroll.left + viewContentWidth < o.data.maxchoicelength ? (o.data.scroll.left = o.data.maxchoicelength - viewContentWidth; refresh(o)) : beep()
        return Handled
    elseif token == :KEY_MOUSE
        (mstate, x, y, _) = getmouse()
        vph = popup_viewport(o)
        if mstate == :scroll_up
            move_cursor!(o.data.scroll, -(round(Int, vph/10)), popup_count(o), vph)
            refresh(o); return Handled
        elseif mstate == :scroll_down
            move_cursor!(o.data.scroll,  round(Int, vph/10),  popup_count(o), vph)
            refresh(o); return Handled
        elseif mstate == :button1_pressed
            (rely, relx) = screen_to_relative(o.window, y, x)
            if o.borderSizeV <= rely < o.height - o.borderSizeV && 0 <= relx < o.width
                o.data.scroll.cursor = clamp(o.data.scroll.top + rely - o.borderSizeV, 1, popup_count(o))
                refresh(o); return Handled
            end
        end
        return Ignored
    end

    return Ignored
end

function helptext(o::TwObj{TwPopupData})
    s = helptext_from_bindings(o)
    o.data.selectmode & POPUPQUICKSELECT != 0 ? s * _POPUP_SEARCHBOX_HELP : s
end
