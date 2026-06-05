# hand-crafted numeric and string input field
#
# This widget is now a thin host over the shared InlineEditor (src/editor.jl):
# `draw` delegates to `draw_editor!`, and `inject` delegates printable/edit keys
# to `editor_handle`, keeping only the entry-specific keys (Enter/Esc/focus_off,
# shift-↑/↓ tick, `m` ×1000, `?`→calendar).

defaultEntryStringHelpText = """
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
ctrl-r : Toggle insertion/overwrite mode

Edges are highlighted if more beyond boundary
"""

defaultEntryNumberHelpText = """
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
,      : Clean up format (add commas)
.      : Decimal point. If already exists, jump there
m      : Multiply by 1,000. So 1mm becomes 1 million
e      : (Floating Point only) exponent. 1e6 for 1,000,000.0
ctrl-r : Toggle insertion/overwrite mode
Shft-up: If configured, increase value by a tick-size
Shft-dn: If configured, decrease value by a tick-size
"""

defaultEntryDateHelpText = """
Format : YYYY-MM-DD standard, but allows formats such as
         20140101, 1/1/2014, 1Jan2014, 1 January 2014
         2014.01.01
<-, -> : move cursor
ctrl-a : move cursor to start
ctrl-e : move cursor to end
ctrl-k : empty entry
,      : Clean up format
ctrl-r : Toggle insertion/overwrite mode
?      : View calendar
Shft-up: If configured, increase value by a tick-size
Shft-dn: If configured, decrease value by a tick-size
"""
mutable struct TwEntryData
    editor::InlineEditor       # the unified inline editor (state + parse/format)
    showHelp::Bool
    helpText::String
    titleLeft::Bool
    titlewidth::Int # -1 = natural title length; >=0 = fixed column width via ensure_length
    limitToWidth::Bool # TODO: not implemented yet
    function TwEntryData(dt::DataType)
        helpText =
            dt <: AbstractString ? defaultEntryStringHelpText :
            dt <: Number ? defaultEntryNumberHelpText :
            (dt <: Date ? defaultEntryDateHelpText : "")
        new(InlineEditor(dt), false, helpText, true, -1, false)
    end
end

# The editor-state fields moved into `editor`, but `inputText`/`cursorPos`/etc.
# are a long-standing public surface (popup/multiselect searchboxes and helper
# entries in the tree widgets read/write them directly). Forward those names to
# the embedded editor so every existing call site keeps working unchanged.
const _ENTRY_EDITOR_FIELDS = Dict{Symbol,Symbol}(
    :inputText => :buffer, :cursorPos => :cursorPos, :fieldLeftPos => :fieldLeftPos,
    :overwriteMode => :overwriteMode, :incomplete => :incomplete, :valueType => :valuetype,
    :tickSize => :tickSize, :precision => :precision, :commas => :commas,
    :stripzeros => :stripzeros, :conversion => :conversion,
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
    width::Real = 30,
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

function inject(o::TwObj{TwEntryData}, token)
    data = o.data
    ed = data.editor
    (fieldcount, _) = getFieldDimension(o)
    ed.width = fieldcount
    dorefresh = false
    retcode = Handled

    if token == :esc
        return Cancel
    elseif token == :enter || token == Symbol("return")
        (v, ok) = editor_commit(ed)
        if ok
            o.value = v
            retcode = Accept
        else
            beep()
        end
    elseif token == :focus_off
        (v, ok) = editor_commit(ed)
        if ok
            o.value = v
            retcode = Accept
        end
        # invalid → editor_commit set `incomplete`; stay focused (retcode Handled)
    elseif token == :shift_up &&
           (ed.valuetype <: Real || ed.valuetype <: Date) && ed.tickSize != 0
        if editor_tick!(ed, 1)
            (v, ok) = editor_commit(ed)
            ok && (o.value = v)
            dorefresh = true
        end
    elseif token == :shift_down &&
           (ed.valuetype <: Real || ed.valuetype <: Date) && ed.tickSize != 0
        if editor_tick!(ed, -1)
            (v, ok) = editor_commit(ed)
            ok && (o.value = v)
            dorefresh = true
        end
    elseif token == "m" && ed.valuetype <: Real && ed.valuetype != Bool  # ×1000
        (v, ok) = editor_commit(ed)
        if ok && v !== missing
            o.value = v * 1000
            ed.buffer = myNumFormat(o.value, ed, fieldcount)
            editor_checkcursor!(ed)
            dorefresh = true
        else
            beep()
        end
    else
        r = editor_handle(ed, token)
        if r === :handled
            dorefresh = true
        elseif r === :rejected || r === :at_left_edge || r === :at_right_edge
            beep()                       # entry has no column nav; edges just beep
        elseif r === :open_calendar
            global rootTwScreen
            (v0, _) = evalNFormat(ed, ed.buffer, fieldcount)
            initd = v0 isa Date ? v0 : today()
            w = newTwCalendar(rootTwScreen, initd; posy = :center, posx = :center)
            activateTwObj(w)
            if w.value isa Date
                editor_set_buffer!(ed, string(w.value))
                editor_checkcursor!(ed)
            end
            unregisterTwObj(rootTwScreen, w)
            dorefresh = true
        else  # :open_enum (entry has no enum) or :ignored → bubble to host
            retcode = Ignored
        end
    end

    if dorefresh
        refresh(o)
    end
    return retcode
end

# Parse/format engine lives in editor.jl. These shims keep the TwEntryData call
# sites working (twedittable/twdicttree build a TwEntryData to drive parsing
# until they migrate to InlineEditor).
myNumFormat(v, data::TwEntryData, fieldcount::Int) = myNumFormat(v, data.editor, fieldcount)
evalNFormat(data::TwEntryData, s::AbstractString, fieldcount::Int) =
    evalNFormat(data.editor, s, fieldcount)

function helptext(o::TwObj{TwEntryData})
    if !o.data.showHelp
        return ""
    end
    o.data.helpText
end
