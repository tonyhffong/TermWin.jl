# twspecentry.jl — a spec-string entry field for the untrusted DataFrameAggrSpec
# grammar (`parseaggr` / `parsedim`).
#
# This is a thin, opinionated host over `newTwEntry(String; ...)` that wires the
# things the raw entry leaves to the caller:
#
#   * a live `hintfn` that runs the *untrusted* safe-grammar parser on every
#     keystroke and echoes what the current text means — a one-line ✓ summary
#     when it parses, or the parser's own rich rejection ("did you mean 'mean'?",
#     column suggestions from `checkcols`) when it does not. Because `hintfn`
#     catches throws, a malformed spec never takes the widget down; the field
#     just shows the diagnostic.
#   * a `?` dropdown of standard spec templates for that kind, so a user who
#     doesn't remember the grammar can pick a starting point and edit it. The
#     field stays free-text (templates are presets, not an enum).
#   * LaTeX-style Tab completion (`latex_complete=true` by default): typing a
#     Julia `\name` and pressing Tab expands it to the char — `\circ`→∘ (the
#     modifier combinator), `\ne`→≠, `\le`→≤, `\ge`→≥ (registered operators) —
#     using Julia's own REPL symbol table. Tab only completes when a `\name` sits
#     before the cursor; otherwise it falls through to focus navigation.
#   * identifier Tab completion: after the `\name` check, Tab completes a partial
#     column or function name against `spec_vocabulary` (the frame's columns +
#     the operator whitelist), advancing to the longest common prefix and opening
#     a picker when still ambiguous. Proactive counterpart to the hint's
#     after-the-fact did-you-mean.
#   * commit gating: the field's `validator` refuses Enter/blur unless the spec
#     parses (empty is allowed), so a form can never harvest an unparseable spec.
#   * F6 details: pops the full, untruncated parse diagnostic (or a structural
#     summary of a valid spec) plus the available columns and operator whitelist
#     in a scrollable viewer — the reference the one-row hint can't fit.
#
# WHAT LIVES WHERE. The *content* of the suggestions — which templates exist for
# a given target/frame/data, the completion vocabulary, and the structural
# rendition of a parsed spec — belongs to DataFrameAggrSpec (`src/templates.jl`:
# `spec_templates`, `spec_vocabulary`, `specsummary`/`specfields`), because it is
# knowledge of the grammar and its registry, not of terminals. That package also
# owns the reverse direction (the did-you-mean repair in `suggest.jl`), so both
# halves of "help the user get the spec right" sit next to the vocabulary they
# read. This file owns only the *presentation*: the ✓/✗ glyphs, the one-row hint
# budget, the F6 pane layout, and the widget wiring.
#
# `kind` selects the grammar:
#   :aggr — an aggregation spec (reduces a column: `sum(_ * wt) / sum(wt)`).
#   :dim  — a dimension spec (a new column from partition-mates:
#           `cumsum(sales) |> orderby(date)`, `rank(sales) |> groupby(region)`).
#
# Pass `columns = propertynames(df)` to have the parser validate every column
# reference in the spec against the frame (with did-you-mean repair) as the user
# types — otherwise a misspelled column only surfaces much later as a bare
# DataFrames indexing error.
#
# The result is a plain `String` (the spec source). Feed it straight back to
# `parsedim`/`parseaggr` at use time — the safe grammar is eval-free, so a string
# harvested from this field is safe to accept.

# ── the diagnostic model ─────────────────────────────────────────────────────
#
# Every rejection of user-typed spec text is a `SpecError` carrying `code`,
# `token`, `fix`, `span` and `spec` beside the prose. This widget reads the
# structured fields for BEHAVIOUR — where to squiggle, what Ctrl-F replaces,
# whether to stay quiet — and shows the parser's own prose for WORDING. It does
# not compose its own diagnostics: the message is DataFrameAggrSpec's human
# contract (its rule G9), and rewording it here would fork it.
#
# The one liberty taken is dropping boilerplate aimed at whoever EMBEDS the
# parser rather than at the analyst typing into this field — the `[in aggr"…"]`
# tag (there is only one spec on screen, and they are looking at it) and the
# `listops()`/`registerop!` aside (advice for host code). Both are removed by
# exact literal, never by pattern-matching the prose, and F6 shows the message
# untouched. Trimming to a display budget is the host's job; rewording is not.

struct SpecDiag
    ok::Bool
    empty::Bool
    code::Symbol
    msg::String                            # full message, exactly as the parser wrote it
    text::String                           # what the panel shows (trimmed; no glyph)
    span::Union{Nothing,UnitRange{Int}}    # CHARACTER range into the buffer
    fix::Union{Nothing,String}             # drop-in replacement for `span`
    incomplete::Bool                       # unfinished text rather than wrong text
end

# Asides addressed to host authors, not to the person in the field.
const _SPEC_DEV_ASIDES = (
    " (listops() shows the whitelist; hosts can extend it with registerop!.)",
)

# The parser's message, minus the parts that only make sense to a host embedding
# it. Every removal is an exact literal built from what we already know (the
# entry-point name, the spec source), so no prose is being parsed.
function _spec_user_msg(msg::AbstractString, specsrc)
    t = String(msg)
    if endswith(t, "]")
        m = findlast(" [in ", t)                      # "… [in aggr\"sum(x)\"]"
        m === nothing || (t = String(t[1:prevind(t, first(m))]))
    end
    for aside in _SPEC_DEV_ASIDES
        t = replace(t, aside => "")
    end
    for p in ("parseaggr: ", "parsedim: ", "checkcols: ")
        if startswith(t, p)
            t = chop(t; head = length(p), tail = 0)
            break
        end
    end
    # checkcols names the spec inline instead of tagging it (that package's open
    # question 1); same redundancy, so the same treatment.
    if specsrc !== nothing
        lead = "spec \"" * String(specsrc) * "\" "
        startswith(t, lead) && (t = chop(t; head = length(lead), tail = 0))
    end
    String(strip(t))
end

# A `SpecError.span` is a BYTE range into the stripped source; the editor's
# cursor and highlight speak 1-based CHARACTERS into the raw buffer. Shift past
# whatever leading whitespace the buffer still carries, then convert. Never
# throws: a span that cannot be placed simply produces no squiggle.
function _spec_span_chars(buf::AbstractString, span::UnitRange{Int})
    lead = ncodeunits(buf) - ncodeunits(lstrip(buf))
    b1, b2 = first(span) + lead, last(span) + lead
    (b1 < 1 || b2 > ncodeunits(buf) || b1 > b2) && return nothing
    try
        c1, c2 = length(buf, 1, b1), length(buf, 1, b2)
        c1 <= c2 ? (c1:c2) : nothing
    catch
        nothing
    end
end

# Parse `buf` and reduce the outcome to what the widget needs to render.
function _spec_analyze(kind::Symbol, columns, buf::AbstractString, target)
    s = strip(buf)
    isempty(s) && return SpecDiag(false, true, :empty, "",
                                  _spec_empty_prompt(kind, target), nothing, nothing, true)
    try
        spec = kind === :aggr ? parseaggr(s; columns=columns) :
                                parsedim(s;  columns=columns)
        SpecDiag(true, false, :ok, "", specsummary(spec), nothing, nothing, false)
    catch err
        if err isa SpecError
            span = err.span === nothing ? nothing : _spec_span_chars(buf, err.span)
            SpecDiag(false, false, err.code, err.msg,
                     _spec_user_msg(err.msg, err.spec), span,
                     err.fix === nothing ? nothing : string(err.fix),
                     err.code === :parse && occursin("incomplete", err.msg))
        else
            m = sprint(showerror, err)
            SpecDiag(false, false, :invalid_spec, m, _spec_user_msg(m, nothing),
                     nothing, nothing, false)
        end
    end
end

# QUIET WHILE TYPING. Typing one correct 21-character spec passes through 17
# rejected intermediate states and 4 valid ones — `sum(`, `su`, `sum(_ * wt) / s`
# are all errors on the way to something right. Shouting at every one of them
# makes the field strobe red while the user does nothing wrong, so two classes
# are reported in a dim, glyph-free register instead:
#
#   * an INCOMPLETE parse — unclosed bracket, trailing operator;
#   * a diagnostic whose span TOUCHES THE CURSOR — the token being typed right
#     now (`su` is not yet `sum`). Adjacency is what makes this possible at all,
#     and it only became computable when the parser started reporting spans.
#
# Neither is suppression: the message still shows, in a dim register without the
# ✗, the squiggle or the Ctrl-F offer.
#
# `committed` ends the politeness. It is the editor's `incomplete` flag — set
# when a commit was attempted and refused (`_spec_valid` never softens; a form
# must not harvest a half-typed spec) — and once the user has said "I am done"
# the widget stops being tactful and shows the error at full strength. That the
# flag is sticky until a *successful* commit is the behaviour we want: after a
# refusal the user is specifically working on the error, which is exactly when
# they want to see it.
function _spec_quiet(d::SpecDiag, buf::AbstractString, cursorPos::Int;
                     committed::Bool = false)
    d.ok && return false
    committed && return false
    d.incomplete && return true
    d.span === nothing && return false
    first(d.span) <= cursorPos <= last(d.span) + 1 && return true
    # The span locator resolves a REPEATED token to its first occurrence (an
    # advisory-precision tradeoff on that side), so a caret sitting on a later
    # copy would otherwise get a squiggle under the earlier one. `sum(x) / sum`
    # is not a corner case — it is the shape of the weighted-mean template — so
    # also stay quiet when the text the diagnostic names is what sits at the
    # caret, whichever occurrence the locator picked.
    _spec_token_ends_at(buf, d.span, cursorPos)
end

# Do the `length(span)` characters ending just before `cursorPos` spell the same
# text as `span`?
function _spec_token_ends_at(buf::AbstractString, span::UnitRange{Int}, cursorPos::Int)
    chars = collect(buf)
    n = length(span)
    lo = cursorPos - n
    (lo < 1 || cursorPos - 1 > length(chars) || last(span) > length(chars)) && return false
    view(chars, lo:cursorPos-1) == view(chars, span)
end

function _spec_empty_prompt(kind::Symbol, target)
    kind === :aggr || return "e.g. cumsum(sales) |> orderby(date)"
    target === nothing ? "e.g. sum(_ * wt) / sum(wt)" : "_ = $(target)   e.g. sum(_)"
end

# Per-widget memo: `draw` asks for the hint, the mark and the fix on every frame,
# and a failing spec is deliberately NOT cached by the parser (only successes
# are), so without this a keystroke would re-parse three times.
mutable struct _SpecDiagCache
    buf::String
    diag::Union{Nothing,SpecDiag}
end
_SpecDiagCache() = _SpecDiagCache("", nothing)

function _spec_diag(c::_SpecDiagCache, kind::Symbol, columns, buf::AbstractString, target)
    if c.diag === nothing || c.buf != buf
        c.buf = String(buf)
        c.diag = _spec_analyze(kind, columns, buf, target)
    end
    c.diag
end

# Glyph and colour for a diagnostic, in the register the quiet rule chose.
_spec_glyph(d::SpecDiag, quiet::Bool) =
    d.empty ? "→ " : d.ok ? "✓ " : quiet ? "… " : "✗ "
_spec_attr(d::SpecDiag, quiet::Bool) =
    (d.ok || d.empty || quiet) ? theme(:divider) : theme(:negative)

# The single-row hint (`hintheight = 1`, and what `newTwEntry`'s plain `hintfn`
# path shows). Same content as the panel, squeezed onto one line.
function _spec_hint(kind::Symbol, columns, buf::AbstractString;
                    target = nothing, cursorPos::Int = typemax(Int),
                    committed::Bool = false,
                    cache::Union{Nothing,_SpecDiagCache} = nothing)
    d = cache === nothing ? _spec_analyze(kind, columns, buf, target) :
                            _spec_diag(cache, kind, columns, buf, target)
    tail = d.empty ? "      (?: templates)" : ""
    _spec_glyph(d, _spec_quiet(d, buf, cursorPos; committed)) * d.text * tail
end

# The multi-row guidance panel. Rows 1..height-1 carry the message (the parser's
# own words, wrapped); the last row is always the action bar, so a long message
# can never push the keys off. Ctrl-F is advertised only when a fix exists AND
# we are being assertive — offering to repair a token the user is still typing
# would fight them.
function _spec_panel(kind::Symbol, columns, buf::AbstractString, width::Int,
                     height::Int; target = nothing, cursorPos::Int = typemax(Int),
                     committed::Bool = false,
                     cache::Union{Nothing,_SpecDiagCache} = nothing)
    d = cache === nothing ? _spec_analyze(kind, columns, buf, target) :
                            _spec_diag(cache, kind, columns, buf, target)
    quiet = _spec_quiet(d, buf, cursorPos; committed)
    rows = Pair{String,TwAttr}[]
    attr = _spec_attr(d, quiet)
    budget = max(height - 1, 1)
    wrapped = wordwrap(_spec_glyph(d, quiet) * d.text, max(width, 8))
    for (i, ln) in enumerate(wrapped)
        i > budget && break
        # a message longer than the panel ends in an ellipsis rather than
        # stopping mid-sentence — F6 has the rest
        txt = String(rstrip(ln))
        i == budget && length(wrapped) > budget && (txt = rstrip(txt, '.') * "…")
        push!(rows, txt => attr)
    end
    while length(rows) < height - 1
        push!(rows, "" => attr)
    end
    acts = String[]
    (!quiet && d.fix !== nothing) && push!(acts, "Ctrl-F fix→" * d.fix)
    push!(acts, "?  templates")
    push!(acts, "F6 details")
    push!(rows, join(acts, "    ") => theme(:divider))
    rows
end

# What Ctrl-F would do to this buffer: the parser's `fix` dropped in at its
# `span`. Only offered when assertive, and never for a `fix` the parser withheld
# — DataFrameAggrSpec sets it only when substituting produces a valid spec
# (its rule G10), so this widget applies it without re-deciding.
function _spec_fix(kind::Symbol, columns, buf::AbstractString;
                   target = nothing, cursorPos::Int = typemax(Int),
                   committed::Bool = false,
                   cache::Union{Nothing,_SpecDiagCache} = nothing)
    d = cache === nothing ? _spec_analyze(kind, columns, buf, target) :
                            _spec_diag(cache, kind, columns, buf, target)
    (d.ok || d.span === nothing || d.fix === nothing) && return nothing
    _spec_quiet(d, buf, cursorPos; committed) && return nothing
    (d.span, d.fix)
end

# Where to squiggle: the offending characters, once we have decided to be
# assertive about them.
function _spec_mark(kind::Symbol, columns, buf::AbstractString;
                    target = nothing, cursorPos::Int = typemax(Int),
                    committed::Bool = false,
                    cache::Union{Nothing,_SpecDiagCache} = nothing)
    d = cache === nothing ? _spec_analyze(kind, columns, buf, target) :
                            _spec_diag(cache, kind, columns, buf, target)
    (d.ok || _spec_quiet(d, buf, cursorPos; committed)) ? nothing : d.span
end

# Commit-time validity: empty is allowed (an unset spec); anything else must
# parse (and, when `columns` is given, reference only real columns). Used as the
# entry's `validator` so a form can't submit a broken spec.
function _spec_valid(kind::Symbol, columns, v::AbstractString)
    isempty(strip(v)) && return true
    try
        kind === :aggr ? parseaggr(v; columns=columns) : parsedim(v; columns=columns)
        true
    catch
        false
    end
end

# Tab identifier completion: the vocabulary is built once and closed over, so
# each keystroke only does the prefix scan.
function _spec_wordlist(kind::Symbol, columns)
    vocab = spec_vocabulary(kind; columns = columns)
    prefix -> String[c for c in vocab if startswith(c, prefix)]
end

const _SPEC_SHAPE_GLOSS = Dict{Symbol,String}(
    :reduce      => "whole column → one value",
    :map         => "one value per row",
    :elementwise => "follows its arguments",
    :filter      => "many values, not row-aligned",
)

# F6 detail text: the full (untruncated) parse diagnostic or the spec's structure
# (`specfields`, laid out here with aligned labels), plus the available columns
# and operator whitelist — the reference the one-row hint can't fit. `templates`
# is the entry's own (already context-narrowed) `?` list, so F6 and `?` never
# disagree.
function _spec_detail(kind::Symbol, columns, buf::AbstractString;
                      templates = nothing, target = nothing, targettype = nothing)
    s = strip(buf)
    lines = String[]
    if isempty(s)
        push!(lines, kind === :aggr ?
            "Aggregation spec — reduces a column to a single value (`_` is the target)." :
            "Dimension spec — computes a new column from partition-mates.")
        if target !== nothing
            push!(lines, "", "  _  =  " * string(target) *
                (targettype === nothing ? "" : "::" * string(targettype)))
        end
        push!(lines, "", "Templates:")
        append!(lines, ["  " * t for t in
                        (templates === nothing ?
                         spec_templates(kind; coltypes=nothing) : templates)])
    else
        try
            spec = kind === :aggr ? parseaggr(s; columns=columns) :
                                    parsedim(s;  columns=columns)
            push!(lines, "✓ parses")
            fields = specfields(spec)
            pad = maximum(length(first(f)) for f in fields)
            for (label, value) in fields
                push!(lines, "  " * rpad(label, pad) * " : " * value)
            end
            # what the head verb returns per input row -- the axis the parser's
            # shape checks reason on, and the one thing `specfields` can't say
            sh = try opshape(spec.fname) catch; :unknown end
            sh === :unknown ||
                push!(lines, "  " * rpad("shape", pad) * " : " * string(sh) *
                      "   (" * _SPEC_SHAPE_GLOSS[sh] * ")")
        catch err
            # The message UNTOUCHED -- the panel trims it to fit a few rows, and
            # this is the place that pays that back.
            push!(lines, "✗ " *
                (err isa ErrorException ? err.msg : sprint(showerror, err)))
            if err isa SpecError
                push!(lines, "", "Diagnostic:")
                push!(lines, "  code  : " * string(err.code))
                err.token === nothing || push!(lines, "  token : " * string(err.token))
                if err.span !== nothing && err.spec !== nothing
                    push!(lines, "  at    : " * repr(err.spec[err.span]))
                end
                err.fix === nothing ||
                    push!(lines, "  fix   : " * string(err.fix) * "   (Ctrl-F applies it)")
            end
        end
    end
    columns === nothing ||
        push!(lines, "", "Available columns: " * join(string.(columns), ", "))
    push!(lines, "", "Operators: " * join(string.(listops()), "  "))
    join(lines, "\n")
end

"""
    newTwSpecEntry(parent, kind::Symbol; columns=nothing, kwargs...) -> TwObj

A single-line entry for a DataFrameAggrSpec spec string, with a live parse hint
and a `?` template dropdown.

* `kind` — `:aggr` (aggregation spec) or `:dim` (dimension spec); selects the
  grammar the live hint parses against and the template list `?` offers.
* `coltypes` — optional column-type information (an `AbstractDataFrame`, a
  `Dict{Symbol,Type}`, or an iterable of `Symbol => Type` pairs). For `:dim` this
  makes the `?` dropdown **type-sensitive** per column; for `:aggr` it gates the
  templates that need a second column (weights, an ordering key). It also
  supplies `columns` for validation when `columns` is not passed explicitly.
* `target` / `targetdata` (`:aggr` only) — the column being aggregated and its
  values in the group the user is looking at. `target`'s type picks the reducer
  set the `?` dropdown offers, and `targetdata` promotes the specs that match
  what the values actually look like (see `spec_templates`). The templates are
  written against `_`, so they never name the target.
* `columns` — optional `AbstractVector{Symbol}` (e.g. `propertynames(df)`); when
  given (or derived from `coltypes`), column references are validated against it
  as the user types, with did-you-mean repair on a misspelling.

All other keyword arguments are forwarded to [`newTwEntry`](@ref) — `key`,
`title`, `width`, `posy`, `posx`, `box`, and even `hintfn`/`choices` if you want
to override the defaults this wrapper supplies. The widget's value is the entered
spec `String`.
"""
function newTwSpecEntry(
    parent::TwObj,
    kind::Symbol;
    columns::Union{Nothing,AbstractVector{Symbol}} = nothing,
    coltypes = nothing,
    target::Union{Nothing,Symbol} = nothing,
    targettype = nothing,
    targetdata = nothing,
    # `title` labels the field and stays SHORT — it is subtracted from the input
    # width, so anything contextual belongs on the border instead. `boxtitle` is
    # that border: for an aggregation it defaults to the target column, which is
    # the one thing an `_`-based spec never says out loud.
    title::AbstractString = (kind === :aggr ? "Aggr spec: " : "Dim spec: "),
    boxtitle::AbstractString = (kind === :aggr && target !== nothing ?
                                string(target) : ""),
    width::SizeSpec = 112,
    choices::Union{Nothing,Vector{String}} = nothing,
    hintfn::Union{Nothing,Function} = nothing,
    hintheight::Int = 4,
    latex_complete::Bool = true,
    kwargs...,
)
    kind in (:aggr, :dim) ||
        error("newTwSpecEntry: kind must be :aggr or :dim, got $(repr(kind))")
    # a df/dict/pairs `coltypes` also names the columns, so validation comes free
    cols = columns !== nothing ? columns : spec_columns(coltypes)
    # target context is aggr-only: a dim spec reads columns by name and has no `_`
    tgt  = kind === :aggr ? target : nothing
    tdat = kind === :aggr ? targetdata : nothing
    tt   = kind !== :aggr ? nothing :
           targettype !== nothing ? targettype :
           tgt !== nothing && spec_coltype(coltypes, tgt) !== nothing ?
               spec_coltype(coltypes, tgt) :
           tdat !== nothing ? eltype(tdat) : nothing
    # One analysis per buffer, shared by the panel, the squiggle and Ctrl-F.
    cache = _SpecDiagCache()
    # The quiet rule needs the caret, which lives in the editor this call is
    # about to build — so the closures read it through a Ref filled on the way
    # out. Before that (and in a headless unit test) the default caret is "far
    # away", i.e. assertive, which is the safe direction: a diagnostic shown
    # too loudly is a nuisance, one suppressed wrongly is a missing error.
    edref = Ref{Any}(nothing)
    curs() = (ed = edref[]; ed === nothing ? typemax(Int) : ed.cursorPos)
    # `incomplete` is raised by a refused commit -- see `_spec_quiet`
    cmtd() = (ed = edref[]; ed !== nothing && ed.incomplete)

    hf = hintfn === nothing ?
         (buf -> _spec_hint(kind, cols, buf; target = tgt, cursorPos = curs(), committed = cmtd(), cache = cache)) :
         hintfn
    pf = hintheight <= 1 ? nothing :
         ((buf, w, h) -> _spec_panel(kind, cols, buf, w, h;
                                     target = tgt, cursorPos = curs(),
                                     committed = cmtd(), cache = cache))
    ch = choices === nothing ?
         spec_templates(kind; coltypes = coltypes, target = tgt,
                        targettype = tt, targetdata = tdat) : choices
    # Tab expands `\circ`→∘, `\ne`→≠, `\le`→≤, `\ge`→≥ — all meaningful in the
    # spec grammar (∘ is the modifier combinator; ≠/≤/≥ are registered operators).
    obj = newTwEntry(parent, String; width = width, title = title, hintfn = hf,
        boxtitle = boxtitle, panelfn = pf, hintheight = hintheight,
        choices = ch, latex_complete = latex_complete,
        word_complete = _spec_wordlist(kind, cols),                      # Tab: column/op names
        validator     = (v -> _spec_valid(kind, cols, v)),               # block invalid commit
        markfn = (buf -> _spec_mark(kind, cols, buf;                     # squiggle the bad token
                                    target = tgt, cursorPos = curs(), committed = cmtd(), cache = cache)),
        fixfn  = (buf -> _spec_fix(kind, cols, buf;                      # Ctrl-F: apply the repair
                                   target = tgt, cursorPos = curs(), committed = cmtd(), cache = cache)),
        detailfn      = (buf -> _spec_detail(kind, cols, buf;            # F6: full diagnostic
                                             templates = ch, target = tgt, targettype = tt)),
        kwargs...)
    edref[] = obj.data.editor
    obj
end

# @twlayout short name: `specentry(:aggr; key=:spec, columns=propertynames(df))`.
# The container is injected as the first arg by the DSL, matching the ctor above.
register_twlayout_widget!(:specentry, newTwSpecEntry)
