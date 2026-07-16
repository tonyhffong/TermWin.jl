# hand-crafted numeric and string input field
#
# This widget is now a thin host over the shared InlineEditor (src/editor.jl):
# `draw` delegates to `draw_editor!`, and `inject` delegates printable/edit keys
# to `editor_handle`, keeping only the entry-specific keys (Enter/Esc/focus_off,
# shift-↑/↓ tick, `m` ×1000, `?`→calendar or preset popup).
#
# Optional guidance features (both off by default):
#   hintfn  : buffer -> String, rendered dimmed on an extra line under the field
#             and recomputed per keystroke — e.g. a live parse echo for DSL text.
#   choices : preset strings; `?` opens an allownew popup whose pick (or typed
#             free text) is written into the buffer for the user to confirm.

mutable struct TwEntryData
    editor::InlineEditor       # the unified inline editor (state + parse/format)
    showHelp::Bool
    titleLeft::Bool
    titlewidth::Int # -1 = natural title length; >=0 = fixed column width via ensure_length
    limitToWidth::Bool # TODO: not implemented yet
    allow_calendar::Bool # `?` opens the calendar even for a non-Date (String) field
    hintfn::Union{Nothing,Function} # buffer -> hint text, redrawn every keystroke on an extra line under the field
    choices::Union{Nothing,Vector{String}} # `?` opens a preset popup (free text still allowed); unlike enumvalues, the field stays free-text
    latex_complete::Bool # Tab completes a `\name` sequence before the cursor into its unicode char (else Tab yields to focus nav)
    word_complete::Union{Nothing,Function} # prefix -> Vector{String}: Tab (after latex) completes the identifier before the cursor against these candidates
    validator::Union{Nothing,Function} # value -> Bool: commit (Enter / blur) is refused unless this passes, so a form never harvests an invalid value
    detailfn::Union{Nothing,Function} # buffer -> String: F6 shows the full text in a scrollable popup (untruncated errors / help)
    TwEntryData(dt::DataType) = new(InlineEditor(dt), false, true, -1, false, false, nothing, nothing, false, nothing, nothing, nothing)
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
    allow_calendar::Bool = false,
    hintfn::Union{Nothing,Function} = nothing,
    choices::Union{Nothing,Vector{String}} = nothing,
    latex_complete::Bool = false,
    word_complete::Union{Nothing,Function} = nothing,
    validator::Union{Nothing,Function} = nothing,
    detailfn::Union{Nothing,Function} = nothing,
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
    data.allow_calendar = allow_calendar # `?` pops the calendar even for a String field
    data.hintfn = hintfn             # live hint line under the field, recomputed per keystroke
    data.choices = choices           # `?` → preset popup that writes into the buffer
    data.latex_complete = latex_complete # Tab expands a `\name` sequence into its unicode char
    data.word_complete = word_complete   # Tab (after latex) completes an identifier prefix
    data.validator = validator           # commit refused unless this passes
    data.detailfn = detailfn             # F6 → full-text popup

    obj = TwObj(data, Val{:Entry})

    obj.box = box
    obj.title = title
    obj.formkey = key
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0

    # hintfn takes one extra row under the input field
    h = (box ? 3 : 1) + (hintfn === nothing ? 0 : 1)
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
    # Live hint line: hintfn(buffer) rendered dimmed under the field, recomputed
    # on every draw (inject refreshes after each handled key). A throwing hintfn
    # must not take the widget down — show the error text instead.
    if o.data.hintfn !== nothing
        hint = try
            string(o.data.hintfn(o.data.editor.buffer))
        catch err
            sprint(showerror, err)
        end
        wattron(o.window, theme(:divider))
        mvwprintw(o.window, starty + 1, o.borderSizeH, "%s",
                  ensure_length(hint, o.width - 2 * o.borderSizeH))
        wattroff(o.window, theme(:divider))
    end
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

# Commit the editor's buffer, then run the optional validator: a value that the
# editor parses but the validator rejects is treated as a failed commit (so a
# form never harvests it). Empty/validator-less fields commit as before.
function _entry_commit(o::TwObj{TwEntryData})
    ed = o.data.editor
    (v, ok) = editor_commit(ed)
    vfn = getfield(o.data, :validator)
    if ok && vfn !== nothing && !(vfn(v)::Bool)
        ok = false
    end
    (v, ok)
end

# Tab identifier completion: locate the word before the cursor and complete it
# against `word_complete(prefix)`. One candidate → insert it; several → advance
# to the longest common prefix, and if that can't extend, open a substring
# picker. Returns true when the Tab was consumed (something happened / a picker
# was shown), false when there is nothing to complete (so Tab can move focus).
function _entry_word_complete!(o::TwObj{TwEntryData})
    ed = o.data.editor
    wc = getfield(o.data, :word_complete)
    w = editor_word_before_cursor(ed)
    w === nothing && return false
    (prefix, sp, ep) = w
    isempty(prefix) && return false
    cands = collect(String, wc(prefix))
    isempty(cands) && return false
    if length(cands) == 1
        editor_replace_range!(ed, sp, ep, cands[1])
        return true
    end
    lcp = longest_common_prefix(cands)
    if length(lcp) > length(prefix)
        editor_replace_range!(ed, sp, ep, lcp)
        return true
    end
    # ambiguous and can't extend → let the user pick
    global rootTwScreen
    popup = newTwPopup(rootTwScreen, sort(cands);
        posy = :center, posx = :center,
        title = "complete '$prefix'",
        substrsearch = true,
        maxheight = min(length(cands) + 2, 12),
        maxwidth = max(maximum(length, cands) + 4, 20),
    )
    pick = activateTwObj(popup)
    unregisterTwObj(rootTwScreen, popup)
    pick !== nothing && editor_replace_range!(ed, sp, ep, pick)
    return true
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
                    (v, ok) = _entry_commit(o)
                    ok ? (o.value = v; Accept) : (beep(); Handled)
                end),
        Binding(:F6, "details",
                when   = _-> getfield(o.data, :detailfn) !== nothing,
                action = _->begin
                    txt = try
                        string(getfield(o.data, :detailfn)(ed.buffer))
                    catch err
                        sprint(showerror, err)
                    end
                    global rootTwScreen
                    v = newTwViewer(rootTwScreen, txt;
                        posy = :center, posx = :center, title = "details")
                    activateTwObj(v)
                    unregisterTwObj(rootTwScreen, v)
                    Handled
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
        Binding("?", "pick preset",
                when   = _-> getfield(o.data, :choices) !== nothing,
                action = _->begin
                    # Preset popup: pick writes into the buffer (no immediate
                    # commit — the user sees the hint line react, then confirms
                    # with Enter). allownew keeps the searchbox usable as a
                    # free-text entry, so `?` never traps the user in the list.
                    global rootTwScreen
                    chs = getfield(o.data, :choices)
                    popup = newTwPopup(rootTwScreen, chs;
                        posy = :center, posx = :center,
                        title = "presets",
                        allownew = true,
                        maxheight = min(length(chs) + 2, 15),
                        maxwidth = max(maximum(length, chs) + 4, 20),
                    )
                    apply_default!(popup, ed.buffer)
                    result = activateTwObj(popup)
                    unregisterTwObj(rootTwScreen, popup)
                    if result !== nothing
                        editor_set_buffer!(ed, result)
                        editor_checkcursor!(ed)
                    end
                    Handled
                end),
        Binding("?", "open calendar",
                when   = _-> ed.valuetype <: Date || getfield(o.data, :allow_calendar),
                action = _->begin
                    (fieldcount, _) = getFieldDimension(o)
                    (v0, _) = evalNFormat(ed, ed.buffer, fieldcount)
                    # For a String field evalNFormat yields the raw text, not a
                    # Date, so seed the calendar from an ISO-parseable buffer;
                    # otherwise (empty/tenor/garbage) fall back to today.
                    initd = v0 isa Date ? v0 :
                            (something(tryparse(Date, strip(ed.buffer)), today()))
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
        (v, ok) = _entry_commit(o)
        if ok
            o.value = v
            return Accept
        end
        return Handled  # invalid → editor set incomplete; stay
    end

    # Tab completion (opt-in), tried in order so neither steps on the other or on
    # focus navigation:
    #   1. LaTeX `\name` → char (\circ → ∘, \ne → ≠)
    #   2. identifier prefix → column / function name (may open a picker)
    # If nothing completes, yield Tab (Ignored) so a form/list cycles focus.
    if token == :tab &&
       (getfield(data, :latex_complete) || getfield(data, :word_complete) !== nothing)
        if getfield(data, :latex_complete) && editor_latex_complete!(ed)
            refresh(o); return Handled
        end
        if getfield(data, :word_complete) !== nothing && _entry_word_complete!(o)
            refresh(o); return Handled
        end
        return Ignored
    end

    # Bindings table (esc, enter, shift_up/down, m, ?)
    r = inject_via_table(o, token)
    r === Handled && refresh(o)
    r !== Ignored && return r

    # Editor handle fallthrough (printable chars, cursor nav, ctrl keys)
    r2 = editor_handle(ed, token)
    if r2 === :handled
        refresh(o); return Handled
    elseif r2 === :at_left_edge || r2 === :at_right_edge
        # Cursor is already at the field boundary: yield the arrow to the host so
        # a layout container can navigate to the sibling column/row (editor.jl
        # documents these edge cases as "host decides"). Standalone use just
        # ignores the key. In-field cursor movement still works until the edge.
        return Ignored
    elseif r2 === :rejected
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
