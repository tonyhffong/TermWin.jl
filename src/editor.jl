# ─── InlineEditor: one inline text editor for scalar/cell/leaf editing ──────────
#
# Unifies the editor that twentry, twedittable, and twdicttree each used to
# re-implement (cursor/h-scroll math, the type-specific keystroke rules, value
# parse/format, and active-field rendering). See
# design/...rearchitecture.md (#9) and the plan.
#
# The editor is strictly WINDOW-FREE: every function except `draw_editor!`
# operates only on the buffer + integer cursor state, so the whole edit model is
# unit-testable headless. Pickers (date `?` → calendar, enum → popup) are full
# widgets needing the host screen, so the editor only *signals* the host
# (`:open_calendar` / `:open_enum`) and the host opens them.

mutable struct InlineEditor
    valuetype::DataType
    buffer::String
    cursorPos::Int            # 1-based; next char goes here
    fieldLeftPos::Int         # leftmost visible width position (string h-scroll)
    width::Int                # field display width (cursor/scroll math + parse hint)
    overwriteMode::Bool
    incomplete::Bool          # last commit/validate failed
    dirty::Bool               # buffer differs from the loaded value
    enumvalues::Union{Nothing,Vector{String}}
    missingok::Bool
    tickSize::Any             # shift-↑/↓ step (entry); 0/nothing disables
    precision::Int
    commas::Bool
    stripzeros::Bool
    conversion::String
end

function InlineEditor(
    valuetype::DataType;
    width::Int = 30,
    enumvalues::Union{Nothing,Vector{String}} = nothing,
    missingok::Bool = false,
    tickSize = 0,
    precision::Int = -1,
    commas::Bool = true,
    stripzeros::Bool = (precision == -1),
    conversion::String = "",
)
    if conversion == ""
        if valuetype <: AbstractString
            conversion = "s"
        elseif valuetype <: Number && valuetype != Bool
            conversion =
                valuetype <: Unsigned ? "x" : (valuetype <: Integer ? "d" : "f")
        end
    end
    InlineEditor(
        valuetype, "", 1, 1, width, false, false, false,
        enumvalues, missingok, tickSize, precision, commas, stripzeros, conversion,
    )
end

# ─── value parse/format engine (relocated from twentry.jl) ──────────────────────
# Raw-parameter core so it has no widget dependency; TwEntryData / InlineEditor
# dispatch wrappers delegate here.

function _myNumFormat(v, fieldcount::Int, precision::Int, commas::Bool,
                      stripzeros::Bool, conversion::String)
    if typeof(v) <: Date
        s = Dates.format(v, "yyyy-mm-dd")
    else
        s = format(v; precision = precision, commas = commas,
                   stripzeros = stripzeros, conversion = conversion)
        if length(s) > fieldcount
            s = replace(s, "," => "", count = length(s) - fieldcount)
        end
    end
    s
end

function _evalNFormat(dt::DataType, s::AbstractString, fieldcount::Int,
                      precision::Int, commas::Bool, stripzeros::Bool, conversion::String)
    fmtnum = v -> _myNumFormat(v, fieldcount, precision, commas, stripzeros, conversion)
    if dt <: AbstractString
        return (s, s)
    elseif dt == Symbol
        return (Symbol(s), s)
    elseif dt == Bool
        if s == "true"
            v = true
        elseif s == "false"
            v = false
        else
            v = nothing
        end
        return v, s
    elseif dt <: AbstractFloat
        v = nothing
        stmp = replace(s, "," => "")
        try
            v = length(stmp) == 0 ? nothing : parse(dt, stmp)
        catch
        end
        if v !== nothing
            v = convert(dt, v)
            return (v, fmtnum(v))
        end
    elseif dt <: Rational
        v = nothing
        stmp = replace(s, "," => "")
        dpos = findfirst(isequal('.'), stmp)
        if dpos === nothing
            try
                v = length(stmp) == 0 ? nothing : parse(dt.types[1], stmp)
            catch
            end
            if v !== nothing
                v = convert(dt, v)
                return (v, fmtnum(v))
            end
        else
            iv = nothing
            fv = nothing
            try
                iv = dpos == 1 ? 0 : parse(dt.types[1], stmp[1:(dpos-1)])
                if dpos == length(stmp)
                    fv = 0 // 1
                else
                    tail = stmp[(dpos+1):end]
                    fv = parse(dt.types[2], tail) // (10^length(tail))
                end
            catch
            end
            if iv !== nothing && fv !== nothing
                v = iv + (sign(iv) > 0 ? fv : -fv)
                return (v, fmtnum(v))
            end
        end
    elseif dt <: Integer # assume int
        v = nothing
        stmp = replace(s, "," => "")
        try
            v = length(stmp) == 0 ? nothing : parse(dt, stmp)
        catch
        end
        if v !== nothing
            v = convert(dt, v)
            return (v, fmtnum(v))
        end
    elseif dt <: Date
        v = nothing
        s = strip(s)
        res = Dict(
            r"^[0-9]{2}[a-z]{3}[0-9]{4}$"i => "dduuuyyyy",
            r"^[0-9][a-z]{3}[0-9]{4}$"i => "duuuyyyy",
            r"^[0-9]{2}[a-z]{3}[0-9]{2}$"i => "dduuuyy",
            r"^[0-9][a-z]{3}[0-9]{2}$"i => "duuuyy",
            r"^[0-9]{2}[a-z]{3}$"i => "dduuu",
            r"^[0-9][a-z]{3}$"i => "duuu",
            r"^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$" => "yyyy-mm-dd",
            r"^[0-9]{4} [0-9]{1,2} [0-9]{1,2}$" => "yyyy mm dd",
            r"^[0-9]{4}.[0-9]{1,2}.[0-9]{1,2}$" => "yyyy.mm.dd",
            r"^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}$" => "yyyy/mm/dd",
            r"^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$" => "mm/dd/yyyy", # assume american
            r"^[0-9]{1,2} +[a-z]{3} +[0-9]{4}$"i => "dd uuu yyyy",
            r"^[0-9]{1,2} +[a-z]{4,} +[0-9]{4}$"i => "dd U yyyy",
            r"^[0-9]{8}$" => "yyyymmdd",
            r"^[0-9]{1,2} [0-9]{1,2}$" => "mm dd",
        )
        fmt = "yyyy-mm-dd"
        for (r, f) in res
            m = match(r, s)
            if m !== nothing
                try
                    v = Date(s, f)
                catch
                end
                if v !== nothing
                    fmt = f
                    if !occursin("yyyy", fmt) && occursin("yy", fmt) && year(v) < 100
                        smally = year(v)
                        thisy = year(today())
                        cent = 100 * div(thisy, 100)
                        if abs(cent + smally - thisy) <= 50
                            v = v + Year(cent)
                        else
                            v = v + Year(cent - 100)
                        end
                        fmt = replace(fmt, "yy" => "yyyy")
                    end
                    if !occursin("y", fmt) && year(v) < 100 # nearest half year
                        smally = year(v)
                        thisy = year(today())
                        if Dates.value(v + Year(thisy - smally + 1) - today()) < 182
                            v = v + Year(thisy - smally + 1)
                        else
                            v = v + Year(thisy - smally)
                        end
                        fmt = "yyyy-mm-dd"
                    end
                    if fmt == "mm/dd/yyyy" || fmt == "yyyymmdd"  # ambiguous
                        fmt = "yyyy-mm-dd"
                    end
                    break
                end
            end
        end
        if v !== nothing
            return (v, Dates.format(v, fmt))
        end
    end
    return (nothing, s)
end

# InlineEditor dispatch wrappers
myNumFormat(v, ie::InlineEditor, fieldcount::Int) =
    _myNumFormat(v, fieldcount, ie.precision, ie.commas, ie.stripzeros, ie.conversion)
evalNFormat(ie::InlineEditor, s::AbstractString, fieldcount::Int) =
    _evalNFormat(ie.valuetype, s, fieldcount, ie.precision, ie.commas, ie.stripzeros, ie.conversion)

# ─── state ──────────────────────────────────────────────────────────────────

function editor_value_to_buf(val, ie::InlineEditor)::String
    val === missing && return ""
    if ie.enumvalues !== nothing || ie.valuetype <: AbstractString || ie.valuetype == Symbol
        return string(val)
    elseif ie.valuetype == Bool
        return string(val)                       # "true" / "false"
    elseif ie.valuetype <: Dates.Date
        return Dates.format(Dates.Date(val), "yyyy-mm-dd")
    elseif ie.valuetype <: Number
        return _myNumFormat(val, ie.width, ie.precision, ie.commas, ie.stripzeros, ie.conversion)
    else
        return string(val)
    end
end

"Load `value` into the editor: format into the buffer, reset cursor/flags."
function editor_load!(ie::InlineEditor, value)
    ie.buffer = editor_value_to_buf(value, ie)
    ie.cursorPos = length(ie.buffer) + 1
    ie.fieldLeftPos = 1
    ie.incomplete = false
    ie.dirty = false
    ie
end

"Clamp the cursor into range and adjust the horizontal scroll for string fields."
function editor_checkcursor!(ie::InlineEditor)
    if ie.buffer == ""
        ie.cursorPos = 1
    else
        ie.cursorPos = max(1, min(length(ie.buffer) + 1, ie.cursorPos))
    end
    if ie.valuetype <: AbstractString || ie.valuetype == Symbol || ie.enumvalues !== nothing
        fieldcount = ie.width
        remainspace = fieldcount - textwidth(ie.buffer)
        if remainspace <= 0
            if ie.cursorPos - ie.fieldLeftPos > fieldcount - 1
                ie.fieldLeftPos = ie.cursorPos - fieldcount + 1
            elseif ie.fieldLeftPos > ie.cursorPos
                ie.fieldLeftPos = ie.cursorPos
            end
        else
            ie.fieldLeftPos = 1
        end
    end
    ie
end

"Insert `s` at the cursor (overwrite-aware) and advance."
function editor_insert!(ie::InlineEditor, s::AbstractString)
    ie.buffer = insertstring(ie.buffer, s, ie.cursorPos, ie.overwriteMode)
    ie.cursorPos += textwidth(s)
    ie.dirty = true
    ie
end

# ─── LaTeX-style unicode completion (opt-in; used by spec entries) ───────────
# Reuse Julia's own REPL table so `\circ`<Tab> → ∘ and `\ne`<Tab> → ≠ behave
# exactly like the REPL. If that internal table is ever unavailable, fall back to
# a small curated set covering the operators the spec grammar cares about.
const _LATEX_FALLBACK = Dict{String,String}(
    "\\circ"=>"∘", "\\ne"=>"≠", "\\neq"=>"≠", "\\le"=>"≤", "\\leq"=>"≤",
    "\\ge"=>"≥", "\\geq"=>"≥", "\\times"=>"×", "\\cdot"=>"⋅", "\\div"=>"÷",
    "\\in"=>"∈", "\\to"=>"→", "\\pm"=>"±", "\\approx"=>"≈",
)
const _LATEX_TABLE = Ref{Union{Nothing,Dict{String,String}}}(nothing)

"The `\\name` → char table used by [`editor_latex_complete!`] (Julia's REPL table, merged over a curated fallback). Built once, then cached."
function latex_symbol_table()
    t = _LATEX_TABLE[]
    t === nothing || return t
    tbl = try
        merge(_LATEX_FALLBACK, Dict{String,String}(REPL.REPLCompletions.latex_symbols))
    catch
        copy(_LATEX_FALLBACK)
    end
    _LATEX_TABLE[] = tbl
    tbl
end

# On Tab in an opt-in editor: if a maximal `\word` sits immediately before the
# cursor and names a known symbol, replace it in place with that char. Returns
# `true` when a replacement happened (caller consumes Tab), `false` otherwise (so
# the host is free to treat Tab as focus navigation). buffer/cursorPos are
# character-indexed; every char involved (backslash, ASCII word, the target
# symbols) is width-1, so a character index equals a display column here.
function editor_latex_complete!(ie::InlineEditor)
    chars = collect(ie.buffer)
    cur = clamp(ie.cursorPos, 1, length(chars) + 1)
    i = cur - 1                                  # last char before the cursor
    (1 <= i <= length(chars)) || return false
    j = i
    while j >= 1 && (isletter(chars[j]) || isdigit(chars[j]))
        j -= 1                                   # walk back over the word body
    end
    (j >= 1 && chars[j] == '\\' && i >= j + 1) || return false   # need `\` + ≥1 char
    repl = get(latex_symbol_table(), "\\" * String(chars[j+1:i]), nothing)
    repl === nothing && return false
    replchars = collect(repl)
    ie.buffer = String(vcat(chars[1:j-1], replchars, chars[i+1:end]))
    ie.cursorPos = (j - 1) + length(replchars) + 1
    ie.dirty = true
    editor_checkcursor!(ie)
    return true
end

# ─── word (identifier) completion (opt-in; used by spec entries) ─────────────
# `\name` latex completion (above) handles operator glyphs; this handles typing
# a partial identifier (column or function name) and completing it against a
# host-supplied vocabulary. The editor only locates/rewrites the word; the host
# owns the candidate list and any disambiguation UI.

_iswordchar(c::AbstractChar) = isletter(c) || isdigit(c) || c == '_'

# The identifier ending immediately at the cursor, as (prefix, startpos, endpos)
# in character indices, or `nothing` when the cursor is not right after a word.
function editor_word_before_cursor(ie::InlineEditor)
    chars = collect(ie.buffer)
    cur = clamp(ie.cursorPos, 1, length(chars) + 1)
    i = cur - 1
    (1 <= i <= length(chars) && _iswordchar(chars[i])) || return nothing
    j = i
    while j >= 1 && _iswordchar(chars[j])
        j -= 1
    end
    (String(chars[j+1:i]), j + 1, i)
end

# Replace the character range [startpos, endpos] with `s`, cursor after it.
function editor_replace_range!(ie::InlineEditor, startpos::Int, endpos::Int, s::AbstractString)
    chars = collect(ie.buffer)
    repl = collect(s)
    ie.buffer = String(vcat(chars[1:startpos-1], repl, chars[endpos+1:end]))
    ie.cursorPos = (startpos - 1) + length(repl) + 1
    ie.dirty = true
    editor_checkcursor!(ie)
    ie
end

# Longest common (case-sensitive) prefix of a candidate list — used to advance a
# completion as far as it is unambiguous before offering a picker.
function longest_common_prefix(strs)
    isempty(strs) && return ""
    p = collect(first(strs))
    for s in strs
        cs = collect(s)
        n = min(length(p), length(cs))
        k = 0
        while k < n && p[k+1] == cs[k+1]
            k += 1
        end
        p = p[1:k]
        isempty(p) && break
    end
    String(p)
end

"Replace the buffer wholesale (e.g. after a calendar/enum picker round-trip)."
function editor_set_buffer!(ie::InlineEditor, s::AbstractString)
    ie.buffer = String(s)
    ie.cursorPos = length(ie.buffer) + 1
    ie.fieldLeftPos = 1
    ie.dirty = true
    ie
end

# ─── keystroke handling ─────────────────────────────────────────────────────

# numeric (non-Bool) insert rules: digit / sign / decimal / exponent / comma.
function _editor_handle_numeric!(ie::InlineEditor, token::AbstractString)
    dt = ie.valuetype
    allowed =
        isdigit(token[1]) ||
        token == "," ||
        (dt <: AbstractFloat && in(token, [".", "e", "+", "-"])) ||
        (dt <: Rational && in(token, [".", "+", "-"])) ||
        (dt <: Signed && in(token, ["+", "-"]))
    allowed || return :rejected

    if token == "e"
        occursin("e", ie.buffer) && return :rejected
        editor_insert!(ie, "e"); return :handled
    elseif token == "-" || token == "+"
        epos = findfirst(isequal('e'), ie.buffer)
        at_start = ie.cursorPos == 1 &&
                   (startswith(ie.buffer, "-") || startswith(ie.buffer, "+"))
        after_e_bad = ie.cursorPos != 1 && (epos === nothing || ie.cursorPos != epos + 1)
        (at_start || after_e_bad) && return :rejected
        editor_insert!(ie, token); return :handled
    elseif token == "."
        dpos = findfirst(isequal('.'), ie.buffer)
        if dpos !== nothing
            ie.cursorPos = dpos + 1
        else
            editor_insert!(ie, ".")
        end
        return :handled
    elseif token == ","  # reformat with grouping
        (v, s) = evalNFormat(ie, ie.buffer, ie.width)
        if v !== nothing
            ie.buffer = s; editor_checkcursor!(ie); ie.incomplete = false; return :handled
        else
            ie.incomplete = true; return :rejected
        end
    else  # digit
        editor_insert!(ie, token); return :handled
    end
end

"""
    editor_handle(ie, token) -> Symbol

Handle one keystroke for the active field. Returns one of:
`:handled` · `:rejected` (beep) · `:at_left_edge` / `:at_right_edge` (cursor at a
bound — host decides) · `:open_calendar` · `:open_enum` · `:ignored` (host's key).
"""
function editor_handle(ie::InlineEditor, token)
    is_enum = ie.enumvalues !== nothing

    # Enum cells have no in-cell text editing — selection happens via a popup.
    if is_enum
        if token isa AbstractString || token == :enter || token == Symbol("return")
            return :open_enum
        elseif token == :ctrl_k && ie.missingok
            ie.buffer = ""; ie.cursorPos = 1; ie.fieldLeftPos = 1; ie.dirty = true
            return :handled
        elseif token == :left
            return :at_left_edge
        elseif token == :right
            return :at_right_edge
        else
            return :ignored
        end
    end

    # navigation / structural edit keys (shared by all value types)
    if token == :left
        ie.cursorPos > 1 || return :at_left_edge
        ie.cursorPos -= 1; editor_checkcursor!(ie); return :handled
    elseif token == :right
        ie.cursorPos < length(ie.buffer) + 1 || return :at_right_edge
        ie.cursorPos += 1; editor_checkcursor!(ie); return :handled
    elseif token == :home || token == :ctrl_a
        ie.cursorPos > 1 || return :rejected
        ie.cursorPos = 1; editor_checkcursor!(ie); return :handled
    elseif token == Symbol("end") || token == :ctrl_e
        newpos = length(ie.buffer) + 1
        ie.cursorPos < newpos || return :rejected
        ie.cursorPos = newpos; editor_checkcursor!(ie); return :handled
    elseif token == :ctrl_r || token == :insert
        ie.overwriteMode = !ie.overwriteMode; return :handled
    elseif token == :ctrl_k
        ie.buffer = ""; ie.cursorPos = 1; ie.fieldLeftPos = 1; ie.dirty = true; return :handled
    elseif token == :delete
        utfs = delete_char_at(ie.buffer, ie.cursorPos)
        utfs == ie.buffer && return :rejected
        ie.buffer = utfs; editor_checkcursor!(ie); ie.dirty = true; return :handled
    elseif token == :backspace
        utfs, newpos = delete_char_before(ie.buffer, ie.cursorPos)
        utfs == ie.buffer && return :rejected
        ie.buffer = utfs; ie.cursorPos = newpos; editor_checkcursor!(ie); ie.dirty = true
        return :handled
    end

    # printable characters: type-specific
    if token isa AbstractString
        if ie.valuetype <: AbstractString || ie.valuetype == Symbol
            editor_insert!(ie, token); editor_checkcursor!(ie); return :handled
        elseif ie.valuetype == Bool
            if token == "t"
                ie.buffer = "true"; ie.cursorPos = 1; ie.dirty = true; return :handled
            elseif token == "f"
                ie.buffer = "false"; ie.cursorPos = 1; ie.dirty = true; return :handled
            else
                return :rejected
            end
        elseif ie.valuetype <: Dates.Date
            if token == "?"
                return :open_calendar
            elseif token == ","
                (v, s) = evalNFormat(ie, ie.buffer, ie.width)
                if v !== nothing
                    ie.buffer = s; editor_checkcursor!(ie); ie.incomplete = false; return :handled
                else
                    ie.incomplete = true; return :rejected
                end
            else
                editor_insert!(ie, token); return :handled
            end
        elseif ie.valuetype <: Number
            return _editor_handle_numeric!(ie, token)
        end
    end

    return :ignored
end

"""
    editor_commit(ie) -> (value, ok::Bool)

Parse the buffer into a value. On success returns `(value, true)` and reformats
the buffer. On failure: if `missingok`, returns `(missing, true)`; otherwise
`(nothing, false)` and sets `incomplete`. (Enum commit is host-side.)
"""
function editor_commit(ie::InlineEditor)
    (v, s) = evalNFormat(ie, ie.buffer, ie.width)
    if v === nothing
        if ie.missingok
            ie.incomplete = false; ie.dirty = false
            return (missing, true)
        end
        ie.incomplete = true
        return (nothing, false)
    end
    ie.buffer = s
    ie.incomplete = false
    ie.dirty = false
    return (v, true)
end

"Shift-↑/↓ tick: bump the current value by `tickSize` (Number) or a Day (Date)."
function editor_tick!(ie::InlineEditor, dir::Int)
    (ie.valuetype <: Real || ie.valuetype <: Dates.Date) || return false
    (ie.tickSize === nothing || ie.tickSize == 0) && ie.valuetype <: Real && return false
    (v, _) = evalNFormat(ie, ie.buffer, ie.width)
    v === nothing && return false
    if ie.valuetype <: Dates.Date
        v = dir > 0 ? v + Dates.Day(1) : v - Dates.Day(1)
    else
        v = dir > 0 ? v + ie.tickSize : v - ie.tickSize
    end
    ie.buffer = _myNumFormat(v, ie.width, ie.precision, ie.commas, ie.stripzeros, ie.conversion)
    editor_checkcursor!(ie)
    ie.incomplete = false
    return true
end

# ─── rendering ──────────────────────────────────────────────────────────────

"""
    editor_render(ie) -> (outstr, rcursPos, leftMore, rightMore)

Window-free: compute the field's display string, the 1-based cursor column within
the field, and whether content overflows left/right (string/enum only). Numbers
are right-justified, dates left, strings horizontally scrolled.
"""
function editor_render(ie::InlineEditor)
    fieldcount = ie.width
    buffer = ie.buffer
    remainspace = fieldcount - textwidth(buffer)
    isnum = ie.valuetype <: Number && ie.valuetype != Bool && ie.enumvalues === nothing
    isdate = ie.valuetype <: Dates.Date && ie.enumvalues === nothing
    local outstr::String, rcursPos::Int
    if isnum
        if remainspace <= 0
            rcursPos = max(1, min(fieldcount, ie.cursorPos))
            outstr = repeat("#", fieldcount - 1) * " "
        else
            rcursPos = max(1, min(remainspace + ie.cursorPos - 1, fieldcount))
            outstr = repeat(" ", remainspace - 1) * buffer * " "
        end
    elseif isdate
        if remainspace <= 0
            rcursPos = max(1, min(fieldcount, ie.cursorPos))
            outstr = repeat("#", fieldcount - 1) * " "
        else
            rcursPos = max(1, min(ie.cursorPos, fieldcount))
            outstr = buffer * repeat(" ", remainspace)
        end
    else  # string or enum
        if remainspace <= 0
            rcursPos = min(fieldcount, max(1, ie.cursorPos - ie.fieldLeftPos + 1))
            outstr = substr_by_width(buffer, ie.fieldLeftPos - 1, fieldcount)
            strw = textwidth(outstr)
            strw < fieldcount && (outstr *= repeat(" ", fieldcount - strw))
        else
            outstr = buffer * repeat(" ", remainspace)
            rcursPos = ie.cursorPos
        end
    end
    hscroll = ie.valuetype <: AbstractString || ie.valuetype == Symbol || ie.enumvalues !== nothing
    leftMore = hscroll && ie.fieldLeftPos > 1
    rightMore = hscroll && (ie.fieldLeftPos + fieldcount <= textwidth(buffer))
    return (outstr, rcursPos, leftMore, rightMore)
end

"""
    draw_editor!(win, y, x, ie, hasFocus; ...)

Render the active field onto `win`. The only window-touching editor function; it
delegates the layout math to `editor_render`. `showcursor=false` suppresses the
cursor (e.g. enum cells in the edit table).
"""
function draw_editor!(
    win, y::Int, x::Int, ie::InlineEditor, hasFocus::Bool;
    focusattr = theme(:selection_focused),
    incompleteattr = COLOR_PAIR(12),
    unfocusattr = theme(:selection_unfocused),
    showcursor::Bool = true,
    incomplete_priority::Bool = false,   # true: show incomplete color even while focused (dict tree)
)
    (outstr, rcursPos, leftMore, rightMore) = editor_render(ie)
    fieldcount = ie.width
    inputflag = incomplete_priority ?
        (ie.incomplete ? incompleteattr : (hasFocus ? focusattr : unfocusattr)) :
        (hasFocus ? focusattr : (ie.incomplete ? incompleteattr : unfocusattr))

    wattron(win, inputflag)
    mvwprintw(win, y, x, "%s", outstr)

    firstflag = inputflag
    lastflag = inputflag
    if showcursor
        c = substr_by_width(outstr, rcursPos - 1, 1)
        flag = ie.overwriteMode ? (inputflag | A_REVERSE) : (inputflag | A_UNDERLINE)
        wattron(win, flag)
        mvwprintw(win, y, x + rcursPos - 1, "%s", string(c))
        wattroff(win, flag)
        rcursPos == 1 && (firstflag = flag)
        rcursPos == fieldcount && (lastflag = flag)
    end

    if leftMore
        c = substr_by_width(outstr, 0, 1)
        wattron(win, firstflag | A_BOLD)
        mvwprintw(win, y, x, "%s", string(c))
        wattroff(win, firstflag | A_BOLD)
    end
    if rightMore
        c = substr_by_width(outstr, fieldcount - 1, 1)
        wattron(win, lastflag | A_BOLD)
        mvwprintw(win, y, x + fieldcount - 1, "%s", string(c))
        wattroff(win, lastflag | A_BOLD)
    end
    wattroff(win, inputflag)
end
