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

# Strip the parser's "parseaggr: " / "parsedim: " / "checkcols: " prefix so the
# one-row hint spends its width on the message, not the bookkeeping.
_strip_spec_prefix(msg::AbstractString) =
    replace(msg, r"^(parseaggr|parsedim|checkcols):\s*" => "")

# The live hint closure body: empty → a prompt with a nudge toward `?`; parses →
# `specsummary` behind a ✓; throws → the parser's own rich diagnostic (kept
# intact bar the prefix). When the host named the aggregation target, the empty
# prompt spells out what `_` stands for — the one thing about an aggr spec that
# isn't in the text.
function _spec_hint(kind::Symbol, columns, buf::AbstractString; target = nothing)
    s = strip(buf)
    if isempty(s)
        kind === :aggr || return "→ e.g. cumsum(sales) |> orderby(date)      (?: templates)"
        return target === nothing ?
            "→ e.g. sum(_ * wt) / sum(wt)      (?: templates)" :
            "→ _ = $(target)   e.g. sum(_)      (?: templates)"
    end
    try
        spec = kind === :aggr ? parseaggr(s; columns=columns) :
                                parsedim(s;  columns=columns)
        return "✓ " * specsummary(spec)
    catch err
        msg = err isa ErrorException ? err.msg : sprint(showerror, err)
        return "✗ " * _strip_spec_prefix(msg)
    end
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
        catch err
            push!(lines, "✗ " *
                (err isa ErrorException ? err.msg : sprint(showerror, err)))
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
    title::AbstractString = (kind === :aggr ? "Aggr spec: " : "Dim spec: "),
    width::SizeSpec = 64,
    choices::Union{Nothing,Vector{String}} = nothing,
    hintfn::Union{Nothing,Function} = nothing,
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
    hf = hintfn === nothing ? (buf -> _spec_hint(kind, cols, buf; target = tgt)) : hintfn
    ch = choices === nothing ?
         spec_templates(kind; coltypes = coltypes, target = tgt,
                        targettype = tt, targetdata = tdat) : choices
    # Tab expands `\circ`→∘, `\ne`→≠, `\le`→≤, `\ge`→≥ — all meaningful in the
    # spec grammar (∘ is the modifier combinator; ≠/≤/≥ are registered operators).
    newTwEntry(parent, String; width = width, title = title, hintfn = hf,
        choices = ch, latex_complete = latex_complete,
        word_complete = _spec_wordlist(kind, cols),                      # Tab: column/op names
        validator     = (v -> _spec_valid(kind, cols, v)),               # block invalid commit
        detailfn      = (buf -> _spec_detail(kind, cols, buf;            # F6: full diagnostic
                                             templates = ch, target = tgt, targettype = tt)),
        kwargs...)
end

# @twlayout short name: `specentry(:aggr; key=:spec, columns=propertynames(df))`.
# The container is injected as the first arg by the DSL, matching the ctor above.
register_twlayout_widget!(:specentry, newTwSpecEntry)
