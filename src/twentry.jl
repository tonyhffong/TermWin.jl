# hand-crafted numeric and string input field
#
# This widget is now a thin host over the shared InlineEditor (src/editor.jl):
# `draw` delegates to `draw_editor!`, and `inject` delegates printable/edit keys
# to `editor_handle`, keeping only the entry-specific keys (Enter/Esc/focus_off,
# shift-↑/↓ tick, `m` ×1000, `?`→calendar).

mutable struct TwEntryData
    editor::InlineEditor       # the unified inline editor (state + parse/format)
    showHelp::Bool
    titleLeft::Bool
    titlewidth::Int # -1 = natural title length; >=0 = fixed column width via ensure_length
    limitToWidth::Bool # TODO: not implemented yet
    TwEntryData(dt::DataType) = new(InlineEditor(dt), false, true, -1, false)
end

# The editor-state fields moved into `editor`, but `inputText`/`cursorPos`/etc.
# are a long-standing public surface (popup/multiselect searchboxes and helper
# entries in the tree widgets read/write them directly). Forward those names to
# the embedded editor so every existing call site keeps working unchanged.
const _ENTRY_EDITOR_FIELDS = Dict{Symbol,Symbol}(
    :inputText => :buffer, :cursorPos => :cursorPos, :fieldLeftPos => :fieldLeftPos,
    :overwriteMode => :overwriteMode, :incomplete => :incomplete, :valueType => :valuetype,
    :tickSize => :tickSize, :precision => :precision, :commas => :commas,
    :stripzeros => :stripzeros, :conversion => :conversion, :enumvalues => :enumvalues,
)
function Base.getproperty(d::TwEntryData, s::Symbol)
    f = get(_ENTRY_EDITOR_FIELDS, s, nothing)
    f === nothing ? getfield(d, s) : getproperty(getfield(d, :editor), f)
end
function Base.setproperty!(d::TwEntryData, s::Symbol, v)
    f = get(_ENTRY_EDITOR_FIELDS, s, nothing)
    f === nothing ? setfield!(d, s, v) : setproperty!(getfield(d, :editor), f, v)
end

# the ways to use it:
# standalone panel
# as a subwin as part of another widget (see next function)
# w include title width, if it's shown on the left

# this one only creates a subwin, do not make a panel out of it, and don't
# register it to a screen
# so to use it, the container widget must keep track of its update and input
# y and x is relative to parentwin
function newTwEntry(
    parent::TwObj,
    dt::DataType;
    width::SizeSpec = 30,
    posy::Any = :staggered,
    posx::Any = :staggered,
    box = true,
    showHelp = true,
    titleLeft = true,
    title = "",
    titlewidth::Int = -1,
    precision = -1,
    stripzeros = (precision == -1),
    conversion = "",
    enumvalues::Union{Nothing,Vector{String}} = nothing,
    key::Union{Nothing,Symbol} = nothing,
)

    data = TwEntryData(dt)
    data.showHelp = showHelp
    data.titleLeft = titleLeft
    data.titlewidth = titlewidth
    data.precision = precision       # forwarded to editor.precision
    data.stripzeros = stripzeros     # forwarded to editor.stripzeros
    if conversion != ""
        data.conversion = conversion # forwarded to editor.conversion
    end
    data.enumvalues = enumvalues     # forwarded to editor.enumvalues; non-nothing → popup picker

    obj = TwObj(data, Val{:Entry})

    obj.box = box
    obj.title = title
    obj.formkey = key
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0

    h = box ? 3 : 1
    link_parent_child(parent, obj, h, width, posy, posx)
    obj
end

function apply_default!(obj::TwObj{TwEntryData}, value)
    value === nothing && return
    (fieldcount, _) = getFieldDimension(obj)
    obj.data.editor.width = fieldcount
    editor_load!(obj.data.editor, value)
    obj.value = value
end

function getFieldDimension(o::TwObj)
    if o.data.titleLeft && !isempty(o.title)
        tw = o.data.titlewidth >= 0 ? o.data.titlewidth : length(o.title)
        fieldcount = o.width - tw - o.borderSizeH * 2
    else
        fieldcount = o.width - (o.box ? 2 : 0)
    end
    remainspacecount = fieldcount - textwidth(o.data.inputText)
    (fieldcount, remainspacecount)
end

function draw(o::TwObj{TwEntryData})
    werase(o.window)
    if o.box
        box(o.window, 0, 0)
    end
    if !isempty(o.title) && !o.data.titleLeft && o.box
        mvwprintw(o.window, 0, round(Int, (o.width - length(o.title))/2), "%s", o.title)
    end
    starty = o.borderSizeV
    startx = o.borderSizeH

    (fieldcount, _) = getFieldDimension(o)
    if o.data.titleLeft && !isempty(o.title)
        if o.data.titlewidth >= 0
            mvwprintw(o.window, starty, startx, "%s", ensure_length(o.title, o.data.titlewidth))
            startx += o.data.titlewidth
        else
            mvwprintw(o.window, starty, startx, "%s", o.title)
            startx += length(o.title)
        end
    end
    # Field rendering (right-justified numbers/dates, cursor, boundary
    # indicators) is the shared InlineEditor renderer.
    o.data.editor.width = fieldcount
    draw_editor!(o.window, starty, startx, o.data.editor, o.hasFocus)
end

const _ENTRY_EDITOR_HELP =
    "←/→ Ctrl-A/E : cursor navigation  Ctrl-K : clear  Ctrl-R : toggle insert/overwrite\n"
const _ENTRY_NUMBER_FORMAT_HELP =
    ",  : reformat with commas  .  : decimal point (or jump to existing)\n"
const _ENTRY_FLOAT_HELP =
    "e  : exponent notation (e.g. 1e6)\n"
const _ENTRY_DATE_FORMAT_HELP =
    "Date formats: YYYY-MM-DD, 20140101, 1Jan2014, 1/1/2014, 2014.01.01\n" *
    ",  : reformat to canonical form\n"

# Enum field (`enumvalues` set): open a substring-searchable popup picker
# instead of free-text entry. Picking a value commits and closes the entry
# immediately (there is no separate "confirm" step for an atomic pick);
# cancelling the popup (Esc) leaves the entry's current value untouched.
function _entry_open_enum_popup!(o::TwObj{TwEntryData})
    global rootTwScreen
    ed = o.data.editor
    (fieldcount, _) = getFieldDimension(o)
    popup = newTwPopup(rootTwScreen, ed.enumvalues;
        posy = :center, posx = :center,
        substrsearch = true,
        maxheight = min(length(ed.enumvalues) + 2, 12),
        maxwidth = max(fieldcount + 4, 20),
    )
    apply_default!(popup, ed.buffer)
    result = activateTwObj(popup)
    unregisterTwObj(rootTwScreen, popup)
    result === nothing && return Handled
    editor_set_buffer!(ed, result)
    (v, ok) = editor_commit(ed)
    if ok
        o.value = v
        return Accept
    else
        beep()
        return Handled
    end
end

# Enum fields skip the free-text box entirely: activating the entry goes
# straight to the popup picker instead of waiting for a keypress first (Enter
# inside an empty/non-editable text box, then Enter again, would be a
# pointless two-step). Non-interactive callers (`tokens` given, e.g. scripted
# replay) fall back to the generic loop.
function activateTwObj(o::TwObj{TwEntryData}, tokens::Any = nothing)
    if tokens === nothing && o.data.enumvalues !== nothing
        status = _entry_open_enum_popup!(o)
        return status == Accept ? o.value : nothing
    end
    invoke(activateTwObj, Tuple{TwObj,Any}, o, tokens)
end

function bindings(o::TwObj{TwEntryData})
    ed = o.data.editor
    [
        Binding(:esc, "cancel", action = _->Cancel),
        Binding([:enter, Symbol("return")], "pick",
                when   = _-> ed.enumvalues !== nothing,
                action = _-> _entry_open_enum_popup!(o)),
        Binding([:enter, Symbol("return")], "confirm",
                when   = _-> ed.enumvalues === nothing,
                action = _->begin
                    (v, ok) = editor_commit(ed)
                    ok ? (o.value = v; Accept) : (beep(); Handled)
                end),
        Binding(:shift_up, "increase by tick",
                when   = _-> (ed.valuetype <: Real || ed.valuetype <: Date) && ed.tickSize != 0,
                action = _->begin
                    if editor_tick!(ed, 1)
                        (v, ok) = editor_commit(ed)
                        ok && (o.value = v)
                    end
                    Handled
                end),
        Binding(:shift_down, "decrease by tick",
                when   = _-> (ed.valuetype <: Real || ed.valuetype <: Date) && ed.tickSize != 0,
                action = _->begin
                    if editor_tick!(ed, -1)
                        (v, ok) = editor_commit(ed)
                        ok && (o.value = v)
                    end
                    Handled
                end),
        Binding("m", "×1000",
                when   = _-> ed.valuetype <: Real && ed.valuetype != Bool,
                action = _->begin
                    (fieldcount, _) = getFieldDimension(o)
                    (v, ok) = editor_commit(ed)
                    if ok && v !== missing
                        o.value = v * 1000
                        ed.buffer = myNumFormat(o.value, ed, fieldcount)
                        editor_checkcursor!(ed)
                    else
                        beep()
                    end
                    Handled
                end),
        Binding("?", "open calendar",
                when   = _-> ed.valuetype <: Date,
                action = _->begin
                    (fieldcount, _) = getFieldDimension(o)
                    (v0, _) = evalNFormat(ed, ed.buffer, fieldcount)
                    initd = v0 isa Date ? v0 : today()
                    global rootTwScreen
                    w = newTwCalendar(rootTwScreen, initd; posy = :center, posx = :center)
                    activateTwObj(w)
                    if w.value isa Date
                        editor_set_buffer!(ed, string(w.value))
                        editor_checkcursor!(ed)
                    end
                    unregisterTwObj(rootTwScreen, w)
                    Handled
                end),
    ]
end

function inject(o::TwObj{TwEntryData}, token)
    data = o.data
    ed = data.editor
    (fieldcount, _) = getFieldDimension(o)
    ed.width = fieldcount

    # focus_off: not a user binding; commit on blur
    if token == :focus_off
        (v, ok) = editor_commit(ed)
        if ok
            o.value = v
            return Accept
        end
        return Handled  # invalid → editor set incomplete; stay
    end

    # Bindings table (esc, enter, shift_up/down, m, ?)
    r = inject_via_table(o, token)
    r === Handled && refresh(o)
    r !== Ignored && return r

    # Editor handle fallthrough (printable chars, cursor nav, ctrl keys)
    r2 = editor_handle(ed, token)
    if r2 === :handled
        refresh(o); return Handled
    elseif r2 === :rejected || r2 === :at_left_edge || r2 === :at_right_edge
        beep(); return Handled
    elseif r2 === :open_enum
        res = _entry_open_enum_popup!(o)
        refresh(o)
        return res
    elseif r2 === :open_calendar
        (v0, _) = evalNFormat(ed, ed.buffer, fieldcount)
        initd = v0 isa Date ? v0 : today()
        global rootTwScreen
        w = newTwCalendar(rootTwScreen, initd; posy = :center, posx = :center)
        activateTwObj(w)
        if w.value isa Date
            editor_set_buffer!(ed, string(w.value))
            editor_checkcursor!(ed)
        end
        unregisterTwObj(rootTwScreen, w)
        refresh(o); return Handled
    end
    return Ignored
end

# Parse/format engine lives in editor.jl. These shims keep the TwEntryData call
# sites working (twedittable/twdicttree build a TwEntryData to drive parsing
# until they migrate to InlineEditor).
myNumFormat(v, data::TwEntryData, fieldcount::Int) = myNumFormat(v, data.editor, fieldcount)
evalNFormat(data::TwEntryData, s::AbstractString, fieldcount::Int) =
    evalNFormat(data.editor, s, fieldcount)

function helptext(o::TwObj{TwEntryData})
    o.data.showHelp || return ""
    t = o.data.editor.valuetype
    helptext_from_bindings(o) *
        _ENTRY_EDITOR_HELP *
        (t <: AbstractFloat ? _ENTRY_NUMBER_FORMAT_HELP * _ENTRY_FLOAT_HELP :
         t <: Real && t != Bool ? _ENTRY_NUMBER_FORMAT_HELP :
         t <: Date ? _ENTRY_DATE_FORMAT_HELP : "")
end
