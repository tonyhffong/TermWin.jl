# Headless test for DfTable layout persistence (TableConfig round-trip).
#
# `table_config(widget)` extracts a table's layout (pivots, visible columns,
# widths, user calc-dimensions, aggregation overrides) as a serializable value;
# `newTwDfTable(df; config=cfg)` hydrates a new table from one. Storage is out of
# scope — this exercises the in-memory widget → config → widget round-trip, the
# plain-Dict conversion, schema resilience, and the untrusted-parse safety of
# hydration. Drives the API directly (not the TTY), mirroring dftable_aggr_unit.jl.
#
# Run:  julia --project=. test/dftable_config_unit.jl

using Test
using TermWin, DataFrames

const _CDF = DataFrame(
    region = ["E", "E", "W", "W", "N"],
    score  = [10.0, 20.0, 5.0, 35.0, 50.0],
    wt     = [1.0, 3.0, 2.0, 2.0, 1.0],
)

const _DIMSPEC = "discretize(score, [0.0, 20.0, 40.0, 60.0])"

session_ok = false
try
    TermWin.initsession()
    global session_ok = true
catch err
    @warn "dftable_config_unit.jl: no Notcurses session available, skipping" err
end

# Build a table and give it a non-trivial layout: a pivot, a user dimension, and
# an aggregation override on `score`.
function _laid_out_table()
    obj = TermWin.newTwDfTable(rootTwScreen, _CDF; pivots = [:region])
    TermWin._dt_add_dimension!(obj, "bucket", _DIMSPEC)
    obj.data.pivots = [:region, :bucket]
    TermWin._dt_rebuild_tree!(obj)
    TermWin._dt_set_aggr!(obj, :score, "maximum(_)")
    obj
end

if session_ok
    try
        @testset "TableConfig extract / Dict round-trip" begin
            obj = _laid_out_table()
            cfg = table_config(obj; name = "by-region")

            @test cfg.name == "by-region"
            @test cfg.pivots == ["region", "bucket"]
            @test cfg.calcpivots["bucket"] == _DIMSPEC
            @test cfg.aggrs["score"] == "maximum(_)"
            @test cfg.schema == sort(String[string(n) for n in names(_CDF)])
            @test "score" in cfg.columns
            @test haskey(cfg.widths, "score")

            # plain-Dict form is a String/Int/Vector/Dict tree, and round-trips
            d = Dict(cfg)
            @test d isa Dict{String,Any}
            @test d["sortorder"] isa Vector          # [[col,dir], ...]
            @test TableConfig(d) == cfg

            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "hydrate: widget → config → widget reproduces the layout" begin
            src = _laid_out_table()
            cfg = table_config(src)
            TermWin.unregisterTwObj(rootTwScreen, src)

            obj = TermWin.newTwDfTable(rootTwScreen, _CDF; config = cfg)
            @test obj.data.pivots == [:region, :bucket]
            @test haskey(obj.data.calcpivots, :bucket)
            # the aggregation override recomputes (max of the whole score column)
            @test obj.data.rootnode[:score] == maximum(_CDF.score)
            # visible column order matches the captured config
            @test String[string(ci.name) for ci in obj.data.colInfo] == cfg.columns
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "hydrate from a plain Dict (as a backend would return)" begin
            src = _laid_out_table()
            d = Dict(table_config(src))
            TermWin.unregisterTwObj(rootTwScreen, src)

            obj = TermWin.newTwDfTable(rootTwScreen, _CDF; config = d)  # Dict, not TableConfig
            @test obj.data.pivots == [:region, :bucket]
            @test obj.data.rootnode[:score] == maximum(_CDF.score)
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "schema resilience: unknown column refs are dropped, not errors" begin
            src = _laid_out_table()
            cfg = table_config(src)           # references region, score, wt + bucket dim
            TermWin.unregisterTwObj(rootTwScreen, src)

            smalldf = select(_CDF, [:region, :score])   # no wt
            obj = TermWin.newTwDfTable(rootTwScreen, smalldf; config = cfg)
            visible = Symbol[ci.name for ci in obj.data.colInfo]
            @test :wt ∉ visible                          # gone column dropped
            @test :region in visible && :score in visible
            @test obj.data.pivots == [:region, :bucket]  # bucket dim (over score) still valid
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "safety: eval-shaped config specs are rejected on hydrate" begin
            @test_throws Exception TermWin.newTwDfTable(rootTwScreen, _CDF;
                config = TableConfig(; aggrs = Dict("score" => "Base.run(`ls`)")))
            @test_throws Exception TermWin.newTwDfTable(rootTwScreen, _CDF;
                config = TableConfig(; calcpivots = Dict("x" => "Base.run(`ls`)")))
        end
    finally
        TermWin.endsession()
    end
end

println("dftable_config_unit.jl: done.")
