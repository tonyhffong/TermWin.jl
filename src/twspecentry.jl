# twspecentry.jl — a spec-string entry field for the untrusted DataFrameAggrSpec
# grammar (`parseaggr` / `parsedim`).
#
# This is a thin, opinionated host over `newTwEntry(String; ...)` that wires two
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
#     column or function name against the frame's columns + the operator
#     whitelist (`listops()`), advancing to the longest common prefix and opening
#     a picker when still ambiguous. Proactive counterpart to the hint's
#     after-the-fact did-you-mean.
#   * commit gating: the field's `validator` refuses Enter/blur unless the spec
#     parses (empty is allowed), so a form can never harvest an unparseable spec.
#   * F6 details: pops the full, untruncated parse diagnostic (or a structural
#     summary of a valid spec) plus the available columns and operator whitelist
#     in a scrollable viewer — the reference the one-row hint can't fit.
#
# `kind` selects the grammar:
#   :aggr — an aggregation spec (reduces a column: `sum(_ * wt) / sum(wt)`).
#   :dim  — a dimension spec (a new column from partition-mates:
#           `cumsum(sales) |> orderby(date)`, `mean(x) |> groupby(region)`).
#
# Pass `columns = propertynames(df)` to have the parser validate every column
# reference in the spec against the frame (with did-you-mean repair) as the user
# types — otherwise a misspelled column only surfaces much later as a bare
# DataFrames indexing error.
#
# The result is a plain `String` (the spec source). Feed it straight back to
# `parsedim`/`parseaggr` at use time — the safe grammar is eval-free, so a string
# harvested from this field is safe to accept.

# Generic starter templates offered by the `?` dropdown when the caller gives no
# column-type information. `_` is the aggregation target placeholder (aggr specs
# only); the sample column names are meant to be edited to the real columns.
const _AGGR_TEMPLATES = String[
    "sum(_)",
    "mean(_)",
    "median(_)",
    "minimum(_)",
    "maximum(_)",
    "std(_)",
    "sum(_ * wt) / sum(wt)",   # weighted mean
    "uniqvalue(_)",
    "strjoinuniq(_)",
]

const _DIM_TEMPLATES = String[
    "cumsum(sales) |> orderby(date)",       # running total within a partition
    "lag(sales) |> orderby(date)",          # previous row's value
    "lead(sales) |> orderby(date)",         # next row's value
    "discretize(score, [0, 20, 40, 60, 80, 100])",  # labeled bins
    "topnames(name, sales, 5)",             # top-5 by measure, rest → "Others"
    "quantiles(score, 4)",                  # quartile bucket
    "mean(sales) |> groupby(region)",       # per-region mean broadcast back
]

# Coarse column families that drive which reducers/verbs are worth suggesting.
# `nonmissingtype` peels `Union{Missing,T}` so a nullable numeric still reads as
# numeric.
function _type_family(T::Type)
    U = nonmissingtype(T)
    U <: Number                              ? :numeric :
    U <: Union{AbstractString,Symbol,AbstractChar} ? :text :
    U <: Dates.TimeType                      ? :date :
    :other
end

# Normalise the many ways a caller can hand us column types into an *ordered*
# vector of `Symbol => Type` pairs (order preserved so the dropdown follows the
# frame's column order). Accepts a DataFrame, a Dict, or any iterable of pairs.
_normalize_coltypes(::Nothing) = nothing
_normalize_coltypes(df::AbstractDataFrame) =
    Pair{Symbol,Type}[n => eltype(df[!, n]) for n in propertynames(df)]
_normalize_coltypes(d::AbstractDict) =
    Pair{Symbol,Type}[Symbol(k) => v for (k, v) in d]
_normalize_coltypes(v) =
    Pair{Symbol,Type}[Symbol(first(p)) => last(p) for p in v]

# Per-column, type-appropriate AGGR reducers: numeric columns get sum/mean/…,
# text columns get uniqvalue/strjoinuniq/…, dates get min/max/first/last. Falls
# back to the generic `_` list when nothing typed is recognised.
function _aggr_templates_for(coltypes)
    out = String[]
    for (c, T) in coltypes
        fam = _type_family(T)
        if fam === :numeric
            append!(out, ["sum($c)", "mean($c)", "median($c)",
                          "maximum($c)", "minimum($c)", "std($c)"])
        elseif fam === :text
            append!(out, ["uniqvalue($c)", "strjoinuniq($c)",
                          "first($c)", "last($c)"])
        elseif fam === :date
            append!(out, ["minimum($c)", "maximum($c)", "first($c)", "last($c)"])
        end
    end
    # generic fallbacks that don't depend on a specific column, kept last so the
    # type-matched suggestions lead
    append!(out, ["sum(_)", "mean(_)", "sum(_ * wt) / sum(wt)"])
    isempty(out) ? copy(_AGGR_TEMPLATES) : unique!(out)
end

# Per-column, type-appropriate DIM verbs: numeric columns get binning + running
# windows (ordered by the first date/other column), text columns get top-N and
# grouped means (measured by the first numeric column, when there is one).
function _dim_templates_for(coltypes)
    nums  = Symbol[c for (c, T) in coltypes if _type_family(T) === :numeric]
    texts = Symbol[c for (c, T) in coltypes if _type_family(T) === :text]
    dates = Symbol[c for (c, T) in coltypes if _type_family(T) === :date]
    order = !isempty(dates) ? first(dates) : (length(nums) > 1 ? nums[1] : nothing)
    measure = isempty(nums) ? nothing : first(nums)
    out = String[]
    for c in nums
        push!(out, "discretize($c, [0, 20, 40, 60, 80, 100])")
        push!(out, "quantiles($c, 4)")
        if order !== nothing && order != c
            push!(out, "cumsum($c) |> orderby($order)")
            push!(out, "lag($c) |> orderby($order)")
        end
    end
    for c in texts
        measure !== nothing && push!(out, "topnames($c, $measure, 5)")
        measure !== nothing && push!(out, "mean($measure) |> groupby($c)")
    end
    isempty(out) ? copy(_DIM_TEMPLATES) : unique!(out)
end

"""
    spec_templates(kind::Symbol; coltypes=nothing) -> Vector{String}

Starter templates for a spec-entry `kind` (`:aggr` or `:dim`) — the same list the
`?` dropdown of [`newTwSpecEntry`](@ref) offers.

When `coltypes` is given the suggestions become **type-sensitive** and concrete:
each numeric column gets `sum`/`mean`/`median`/… , each string/symbol column gets
`uniqvalue`/`strjoinuniq`/… , each date column gets `minimum`/`maximum`/… (aggr);
dim mode binning/window verbs go to numeric columns and top-N/grouped means to
text columns. Without `coltypes` the generic `_`-placeholder list is returned.

`coltypes` may be an `AbstractDataFrame` (column → `eltype`), a `Dict{Symbol,Type}`,
or any iterable of `Symbol => Type` pairs; order is preserved.
"""
function spec_templates(kind::Symbol; coltypes = nothing)
    ct = _normalize_coltypes(coltypes)
    if kind === :aggr
        ct === nothing ? copy(_AGGR_TEMPLATES) : _aggr_templates_for(ct)
    elseif kind === :dim
        ct === nothing ? copy(_DIM_TEMPLATES) : _dim_templates_for(ct)
    else
        error("spec_templates: kind must be :aggr or :dim, got $(repr(kind))")
    end
end

# Strip the parser's "parseaggr: " / "parsedim: " / "checkcols: " prefix so the
# one-row hint spends its width on the message, not the bookkeeping.
_strip_spec_prefix(msg::AbstractString) =
    replace(msg, r"^(parseaggr|parsedim|checkcols):\s*" => "")

# One-line ✓ summary of a spec that parsed. Both spec structs carry `.fname` and
# `.cols`; a dim spec additionally reports its inferred kind (pivot when it has a
# `groupby`, window when it has an `orderby`).
function _spec_summary(spec)
    if spec isa SafeAggrSpec
        cols = join(string.(spec.cols), ", ")
        return "✓ reduce via $(spec.fname)   [cols: $(isempty(cols) ? "—" : cols)]"
    else # SafeDimSpec
        tags = String[]
        isempty(spec.by)    || push!(tags, "pivot by " * join(string.(spec.by), ", "))
        isempty(spec.order) || push!(tags, "ordered by " *
                                     join(string.(first.(spec.order)), ", "))
        isempty(tags) && push!(tags, "window")
        return "✓ $(spec.fname)   [" * join(tags, "; ") * "]"
    end
end

# The live hint closure body: empty → a prompt with a nudge toward `?`; parses →
# summary; throws → the parser's own rich diagnostic (kept intact bar the prefix).
function _spec_hint(kind::Symbol, columns, buf::AbstractString)
    s = strip(buf)
    if isempty(s)
        return kind === :aggr ?
            "→ e.g. sum(_ * wt) / sum(wt)      (?: templates)" :
            "→ e.g. cumsum(sales) |> orderby(date)      (?: templates)"
    end
    try
        spec = kind === :aggr ? parseaggr(s; columns=columns) :
                                parsedim(s;  columns=columns)
        return _spec_summary(spec)
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

# Tab identifier completion vocabulary: the frame's columns plus the whitelisted
# function names (`listops()`), plus the two dim modifiers. Operator glyphs like
# `+`/`==` are dropped (not identifier-completable — `\name`+Tab handles those).
function _spec_wordlist(kind::Symbol, columns)
    ops = String[string(o) for o in listops() if isletter(first(string(o)))]
    kind === :dim && append!(ops, ["orderby", "groupby"])
    cols = columns === nothing ? String[] : String[string(c) for c in columns]
    vocab = sort!(unique!(vcat(cols, ops)))
    prefix -> String[c for c in vocab if startswith(c, prefix)]
end

# F6 detail text: the full (untruncated) parse diagnostic or a structural summary
# of a valid spec, plus the available columns and operator whitelist — the
# reference the one-row hint can't fit.
function _spec_detail(kind::Symbol, columns, buf::AbstractString)
    s = strip(buf)
    lines = String[]
    if isempty(s)
        push!(lines, kind === :aggr ?
            "Aggregation spec — reduces a column to a single value (`_` is the target)." :
            "Dimension spec — computes a new column from partition-mates.")
        push!(lines, "", "Templates:")
        append!(lines, ["  " * t for t in spec_templates(kind; coltypes=nothing)])
    else
        try
            spec = kind === :aggr ? parseaggr(s; columns=columns) :
                                    parsedim(s;  columns=columns)
            push!(lines, "✓ parses")
            push!(lines, "  function : $(spec.fname)")
            push!(lines, "  columns  : " * join(string.(spec.cols), ", "))
            if spec isa SafeDimSpec
                isempty(spec.by)    || push!(lines, "  group by : " *
                    join(string.(spec.by), ", ") * "   (pivot kind)")
                isempty(spec.order) || push!(lines, "  order by : " *
                    join(string.(first.(spec.order)), ", ") * "   (window kind)")
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
  `Dict{Symbol,Type}`, or an iterable of `Symbol => Type` pairs). When given, the
  `?` dropdown becomes **type-sensitive**: numeric columns are offered
  `sum`/`median`/…, string/symbol columns `uniqvalue`/`strjoinuniq`/…, etc. (see
  [`spec_templates`](@ref)). It also supplies `columns` for validation when
  `columns` is not passed explicitly.
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
    title::AbstractString = (kind === :aggr ? "Aggr spec: " : "Dim spec: "),
    width::SizeSpec = 64,
    choices::Union{Nothing,Vector{String}} = nothing,
    hintfn::Union{Nothing,Function} = nothing,
    latex_complete::Bool = true,
    kwargs...,
)
    kind in (:aggr, :dim) ||
        error("newTwSpecEntry: kind must be :aggr or :dim, got $(repr(kind))")
    ct = _normalize_coltypes(coltypes)
    # a df/dict/pairs `coltypes` also names the columns, so validation comes free
    cols = columns !== nothing ? columns :
           ct !== nothing ? Symbol[first(p) for p in ct] : nothing
    hf = hintfn === nothing ? (buf -> _spec_hint(kind, cols, buf)) : hintfn
    ch = choices === nothing ? spec_templates(kind; coltypes = ct) : choices
    # Tab expands `\circ`→∘, `\ne`→≠, `\le`→≤, `\ge`→≥ — all meaningful in the
    # spec grammar (∘ is the modifier combinator; ≠/≤/≥ are registered operators).
    newTwEntry(parent, String; width = width, title = title, hintfn = hf,
        choices = ch, latex_complete = latex_complete,
        word_complete = (prefix -> _spec_wordlist(kind, cols)(prefix)),  # Tab: column/op names
        validator     = (v -> _spec_valid(kind, cols, v)),               # block invalid commit
        detailfn      = (buf -> _spec_detail(kind, cols, buf)),           # F6: full diagnostic
        kwargs...)
end

# @twlayout short name: `specentry(:aggr; key=:spec, columns=propertynames(df))`.
# The container is injected as the first arg by the DSL, matching the ctor above.
register_twlayout_widget!(:specentry, newTwSpecEntry)
