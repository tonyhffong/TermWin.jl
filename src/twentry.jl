# hand-crafted numeric and string input field
#
# This widget is now a thin host over the shared InlineEditor (src/editor.jl):
# `draw` delegates to `draw_editor!`, and `inject` delegates printable/edit keys
# to `editor_handle`, keeping only the entry-specific keys (Enter/Esc/focus_off,
# shift-↑/↓ tick, `m` ×1000, `?`→calendar or preset popup).
#
# Optional guidance features (all off by default):
#   hintfn  : buffer -> String, rendered dimmed on ONE extra line under the field
#             and recomputed per keystroke — e.g. a live parse echo for DSL text.
#   panelfn : buffer, width, height -> Vector{Pair{String,TwAttr}}, the multi-row
#             counterpart of `hintfn` for guidance a single row cannot hold (a
#             parser diagnostic runs to 156 characters on average). Each row
#             carries its own attribute, so severity can be coloured per line.
#             Takes `hintheight` rows; wins over `hintfn` when both are given.
#   markfn  : buffer -> Union{Nothing,UnitRange{Int}}, a CHARACTER range of the
#             buffer to mark in the field itself (`InlineEditor.highlight`) —
#             pointing at the offending text of whatever `panelfn` is reporting.
#   fixfn   : buffer -> Union{Nothing,Tuple{UnitRange{Int},String}}, a one-key
#             repair offered on Ctrl-F: replace that character range with that
#             string. Only offer one that is known to produce a valid value —
#             the user will apply it without checking.
#   choices : preset strings; `?` opens an allownew popup whose pick (or typed
#             free text) is written into the buffer for the user to confirm.
#
# Captions. `title` labels the FIELD and is subtracted from the input width, so
# a long one is paid for in typing room; `boxtitle` captions the WIDGET on the
# top border, which is free. Use `title` for what the field is ("Aggr spec:")
# and `boxtitle` for what it is about (the column being aggregated).
# `titleLeft = false` is the older way to reach the border: it moves `title`
# there instead of inline, for a label too long to sit beside the input. Both
# land in the same border slot — `boxtitle` wins if both are set — so pick one.

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
    panelfn::Union{Nothing,Function}  # buffer,width,height -> Vector{Pair{String,TwAttr}}: multi-row hint area
    hintheight::Int                   # rows reserved for panelfn (hintfn always takes 1)
    boxtitle::String                  # caption on the TOP BORDER (needs box=true); what this field is about, as opposed to `title`, which labels the field itself. `titleLeft=false` feeds the same slot with `title`
    markfn::Union{Nothing,Function}   # buffer -> Union{Nothing,UnitRange{Int}}: character range to mark in the field
    fixfn::Union{Nothing,Function}    # buffer -> Union{Nothing,Tuple{UnitRange{Int},String}}: Ctrl-F one-key repair
    TwEntryData(dt::DataType) = new(InlineEditor(dt), false, true, -1, false, false, nothing, nothing, false, nothing, nothing, nothing,
                                    nothing, 1, "", nothing, nothing)
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
    panelfn::Union{Nothing,Function} = nothing,
    hintheight::Int = 1,
    boxtitle::AbstractString = "",
    markfn::Union{Nothing,Function} = nothing,
    fixfn::Union{Nothing,Function} = nothing,
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
    data.panelfn = panelfn               # multi-row hint area (wins over hintfn)
    data.hintheight = max(hintheight, 1) # rows the panel gets
    data.boxtitle = String(boxtitle)     # caption on the top border
    data.markfn = markfn                 # character range to mark in the field
    data.fixfn = fixfn                   # Ctrl-F one-key repair

    obj = TwObj(data, Val{:Entry})

    obj.box = box
    obj.title = title
    obj.formkey = key
    obj.borderSizeV = box ? 1 : 0
    obj.borderSizeH = box ? 1 : 0

    # the guidance area takes extra rows under the input field: one for a
    # `hintfn`, `hintheight` for the multi-row `panelfn`
    h = (box ? 3 : 1) + (panelfn !== nothing ? max(hintheight, 1) :
                         hintfn !== nothing  ? 1 : 0)
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
    # ONE writer to the top border. Two kwargs feed it, because they are the
    # same idea found twice: `boxtitle` is the caption proper (a second label,
    # coexisting with an inline one), and `titleLeft = false` is the older
    # spelling — it *relocates* the field's own label there, for a title too
    # long to sit inline without squeezing the input to nothing. They used to
    # draw separately and would silently overwrite each other on row 0; now the
    # explicit `boxtitle` simply wins. Column 2 matches where TwList puts its
    # title, and the text is truncated to stop short of the corners.
    if o.box
        cap = !isempty(getfield(o.data, :boxtitle)) ? getfield(o.data, :boxtitle) :
              !o.data.titleLeft ? o.title : ""
        isempty(cap) ||
            mvwprintw(o.window, 0, 2, "%s", ensure_length(cap, o.width - 4, false))
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
    # indicators) is the shared InlineEditor renderer. A `markfn` points it at
    # the offending characters of whatever the guidance area is reporting; like
    # `hintfn` it must not be able to take the widget down.
    o.data.editor.width = fieldcount
    o.data.editor.highlight = if getfield(o.data, :markfn) === nothing
        nothing
    else
        try
            getfield(o.data, :markfn)(o.data.editor.buffer)
        catch
            nothing
        end
    end
    draw_editor!(o.window, starty, startx, o.data.editor, o.hasFocus)

    avail = o.width - 2 * o.borderSizeH
    if getfield(o.data, :panelfn) !== nothing
        # Multi-row guidance area. panelfn owns the wrapping (it is told the
        # width) and the per-row attribute; we only clip to the reserved rows.
        rows = try
            getfield(o.data, :panelfn)(o.data.editor.buffer, avail,
                                       getfield(o.data, :hintheight))
        catch err
            Pair{String,TwAttr}[sprint(showerror, err) => theme(:negative)]
        end
        for (i, row) in enumerate(rows)
            i > getfield(o.data, :hintheight) && break
            (txt, attr) = row isa Pair ? (first(row), last(row)) :
                                         (string(row), theme(:divider))
            isempty(txt) && continue
            wattron(o.window, attr)
            mvwprintw(o.window, starty + i, o.borderSizeH, "%s",
                      ensure_length(txt, avail))
            wattroff(o.window, attr)
        end
    elseif o.data.hintfn !== nothing
        # Live hint line: hintfn(buffer) rendered dimmed under the field,
        # recomputed on every draw (inject refreshes after each handled key). A
        # throwing hintfn must not take the widget down — show the error instead.
        hint = try
            string(o.data.hintfn(o.data.editor.buffer))
        catch err
            sprint(showerror, err)
        end
        wattron(o.window, theme(:divider))
        mvwprintw(o.window, starty + 1, o.borderSizeH, "%s", ensure_length(hint, avail))
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
        # `editor_commit` cleared the flag on its way out (the text parsed as the
        # field's type); a validator rejection has to raise it again, or the
        # field renders as clean while holding a value it just refused. That
        # flag is `incomplete`'s stated meaning -- "last commit/validate failed"
        # -- and guidance keyed on it (twspecentry's quiet rule) reads it to know
        # the user has said they are done.
        ed.incomplete = true
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

# The repair `fixfn` currently offers for the buffer, or `nothing`. Validated
# here rather than in the binding so a provider that returns a stale or
# out-of-range span can only cost us the key, not corrupt the buffer.
function _entry_pending_fix(o::TwObj{TwEntryData})
    f = getfield(o.data, :fixfn)
    f === nothing && return nothing
    fx = try
        f(o.data.editor.buffer)
    catch
        nothing
    end
    fx === nothing && return nothing
    (r, repl) = fx
    n = length(o.data.editor.buffer)
    (first(r) >= 1 && last(r) <= n && first(r) <= last(r)) || return nothing
    (r, string(repl))
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
        # One-key repair. `fixfn` returns the character range to replace and the
        # replacement; the contract is that applying it yields a valid value, so
        # this does not second-guess it. `when` runs the provider, so the key is
        # absent from the footer/F1 help until there is something to fix.
        Binding(:ctrl_f, "fix",
                when   = _-> getfield(o.data, :fixfn) !== nothing &&
                             _entry_pending_fix(o) !== nothing,
                action = _->begin
                    fx = _entry_pending_fix(o)
                    if fx === nothing
                        beep()
                    else
                        (r, repl) = fx
                        editor_replace_range!(ed, first(r), last(r), repl)
                    end
                    Handled
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
