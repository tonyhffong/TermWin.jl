# Headless test for runtime user-typed pivot dimensions (the `P` binding path).
#
# A DfTable user can type a dimension spec into a text field; it is parsed by the
# UNTRUSTED safe whitelist grammar (parsedim -- no eval, bare-identifier columns,
# `|> groupby(col)` for per-group pivots) and registered as a calculated pivot.
# This drives the underlying `_dt_add_dimension!` + rebuild directly (not the TTY
# entry widgets) and asserts the resulting tree, plus the safety rejections.
#
# Run:  julia --project=. test/dftable_userdim_unit.jl

using Test
using TermWin, DataFrames

const _UDF = DataFrame(
    region   = ["E", "E", "E", "W", "W", "W", "W", "N"],
    district = ["a", "b", "c", "d", "e", "f", "g", "h"],
    score    = [10.0, 20.0, 30.0, 5.0, 15.0, 25.0, 35.0, 50.0],
)

function _sig(n, lines = String[])
    isempty(n.pivotvals) || push!(
        lines,
        string(length(n.pivotcols), "|", n.pivotcols[end], "=",
               n.pivotvals[end], "|n=", size(n.subdataframe, 1)),
    )
    for c in n.children
        _sig(c, lines)
    end
    lines
end

# Add a user dimension named `nm` from safe-grammar `spec`, apply it as a pivot
# (optionally after `base` pivots), rebuild, and return the sorted tree signature.
function _apply_userdim(obj, nm, spec; base = Symbol[])
    sym = TermWin._dt_add_dimension!(obj, nm, spec)
    obj.data.pivots = Symbol[base..., sym]
    TermWin._dt_rebuild_tree!(obj)
    sort(_sig(obj.data.rootnode))
end

session_ok = false
try
    TermWin.initsession()
    global session_ok = true
catch err
    @warn "dftable_userdim_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        @testset "DfTable user-typed dimensions (safe grammar)" begin
            @testset "row-level discretize (window, no groupby)" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _UDF)
                sig = _apply_userdim(obj, "q", "discretize(score, [0.0, 20.0, 40.0, 60.0])")
                @test sig == [
                    "1|q=2. [0,20)|n=3",
                    "1|q=3. [20,40)|n=4",
                    "1|q=4. [40,60)|n=1",
                ]
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "per-group discretize via |> groupby (pivot)" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _UDF;
                    aggrHints = Dict{Any,Any}(:score => :(sum(:_))))
                sig = _apply_userdim(obj, "bucket",
                    "discretize(score, [0.0, 50.0, 100.0]) |> groupby(region)";
                    base = Symbol[])
                # one region-sum bucket (E=60,W=80,N=50 all in [50,100))
                @test "1|bucket=3. [50,100)|n=8" in sig
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "topnames auto-infers pivot" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _UDF;
                    aggrHints = Dict{Any,Any}(:score => :(sum(:_))))
                sig = _apply_userdim(obj, "top1", "topnames(district, score, 1)")
                @test sig == ["1|top1=1. h|n=1", "1|top1=Others|n=7"]
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "safety: invalid / eval-shaped specs are rejected" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _UDF)
                # qualified call / eval attempt -> rejected by the whitelist grammar
                @test_throws Exception TermWin._dt_add_dimension!(obj, "x", "Base.run(`ls`)")
                @test_throws Exception TermWin._dt_add_dimension!(obj, "x", "@eval 1")
                # empty name
                @test_throws Exception TermWin._dt_add_dimension!(obj, "  ", "discretize(score,[0.0])")
                # collides with a real data column
                @test_throws Exception TermWin._dt_add_dimension!(obj, "score", "discretize(score,[0.0])")
                # nothing was registered by the failed calls
                @test !haskey(obj.data.calcpivots, :x)
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end
        end
    finally
        TermWin.endsession()
    end
end
