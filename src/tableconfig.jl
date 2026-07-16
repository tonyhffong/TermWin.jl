# tableconfig.jl — a serializable snapshot of a DataFrame-table layout.
#
# `TableConfig` captures the user-meaningful state of a `newTwDfTable`: which
# pivots are applied, which columns are visible and in what order, their widths,
# any user-typed calculated dimensions, and any per-column aggregation overrides.
# It is deliberately backend-neutral — `table_config(widget)` extracts one off a
# finished table, `Dict(cfg)` turns it into a plain `Dict{String,Any}` any
# serializer (TOML/JSON/DB) can persist, and `newTwDfTable(df; config=cfg)`
# hydrates a new table from one. (Storage itself is intentionally out of scope.)
#
# SECURITY: the calc-dimension and aggregation entries are stored as their
# UNTRUSTED safe-grammar SOURCE strings (`SafeDimSpec.source` / `SafeAggrSpec.source`).
# Hydration re-parses them with `parsedim`/`parseaggr` (no eval), so a config is
# safe to load from disk or accept from another user — it can declare
# aggregations/dimensions but cannot execute arbitrary code.
#
# `name` + `schema` (sorted source column names) exist so a future store can key
# many configs in one place ("union of named"): match by an explicit label, or
# fall back to the column-shape signature.

struct TableConfig
    name::String                              # optional label ("" = unnamed)
    schema::Vector{String}                    # sorted source column names
    pivots::Vector{String}
    columns::Vector{String}                   # visible order
    sortorder::Vector{Tuple{String,String}}   # (col, "asc"|"desc")
    initdepth::Int
    widths::Dict{String,Int}                  # per-column width overrides
    calcpivots::Dict{String,String}           # name => SafeDimSpec.source
    aggrs::Dict{String,String}                # col  => SafeAggrSpec.source (overrides only)
end

# Keyword constructor so callers/extractors can supply just the parts they have.
function TableConfig(;
    name::AbstractString = "",
    schema = String[],
    pivots = String[],
    columns = String[],
    sortorder = Tuple{String,String}[],
    initdepth::Integer = 1,
    widths = Dict{String,Int}(),
    calcpivots = Dict{String,String}(),
    aggrs = Dict{String,String}(),
)
    TableConfig(
        String(name),
        String[string(s) for s in schema],
        String[string(p) for p in pivots],
        String[string(c) for c in columns],
        Tuple{String,String}[(string(a), string(b)) for (a, b) in sortorder],
        Int(initdepth),
        Dict{String,Int}(string(k) => Int(v) for (k, v) in widths),
        Dict{String,String}(string(k) => string(v) for (k, v) in calcpivots),
        Dict{String,String}(string(k) => string(v) for (k, v) in aggrs),
    )
end

function Base.:(==)(a::TableConfig, b::TableConfig)
    a.name == b.name && a.schema == b.schema && a.pivots == b.pivots &&
        a.columns == b.columns && a.sortorder == b.sortorder &&
        a.initdepth == b.initdepth && a.widths == b.widths &&
        a.calcpivots == b.calcpivots && a.aggrs == b.aggrs
end

# ---- backend-neutral serialization -----------------------------------------
# `sortorder` becomes a Vector of 2-element String arrays so the whole thing is a
# tree of String/Int/Vector/Dict — directly TOML/JSON-encodable.
function Base.Dict(cfg::TableConfig)
    Dict{String,Any}(
        "name"       => cfg.name,
        "schema"     => cfg.schema,
        "pivots"     => cfg.pivots,
        "columns"    => cfg.columns,
        "sortorder"  => [[c, d] for (c, d) in cfg.sortorder],
        "initdepth"  => cfg.initdepth,
        "widths"     => cfg.widths,
        "calcpivots" => cfg.calcpivots,
        "aggrs"      => cfg.aggrs,
    )
end

# Inverse of `Dict(cfg)`, tolerant of missing keys (a hand-written or partial
# config still loads). Accepts the `[col, dir]` array shape or `(col, dir)` tuples
# for sortorder.
function TableConfig(d::AbstractDict)
    g(k, default) = get(d, k, get(d, Symbol(k), default))
    so = [(string(p[1]), string(p[2])) for p in g("sortorder", Any[])]
    TableConfig(;
        name       = g("name", ""),
        schema     = g("schema", String[]),
        pivots     = g("pivots", String[]),
        columns    = g("columns", String[]),
        sortorder  = so,
        initdepth  = g("initdepth", 1),
        widths     = g("widths", Dict{String,Int}()),
        calcpivots = g("calcpivots", Dict{String,String}()),
        aggrs      = g("aggrs", Dict{String,String}()),
    )
end
