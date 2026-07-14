# Golden regression for the DfTable calculated-pivot tree.
#
# Freezes the pivot-tree structure produced by the three calcpivot kinds that
# twdftable.jl drives through DataFrameAggrSpec dimensions:
#   * discretize with a `by` (per-group bucketing of an aggregated measure),
#   * discretize row-level (window dimension, no `by`),
#   * topnames (classifier verb; its name column is the auto-inferred group key).
#
# This is the safety net for the DataFrameAggrSpec adoption migration: the
# calcpivot path moved off the legacy CalcPivot shim onto the dimension engine
# (`dim` + `dimspec` chains). These asserted signatures were captured under the
# legacy engine and MUST stay byte-for-byte identical -- the specs below now use
# the canonical `dimspec(...)` surface, so an unchanged tree also proves the
# CalcPivot -> dimspec conversion is behavior-preserving.
#
# It also locks down a fix landed alongside it: rebuildColumns! must treat
# calcpivot names as "present" so its schema-resilience filter doesn't drop
# calcpivot pivot levels.
#
# Run:  julia --project=. test/dftable_pivot_golden.jl

using Test
using TermWin, DataFrames

const _GDF = DataFrame(
    region   = ["E", "E", "E", "W", "W", "W", "W", "N"],
    district = ["a", "b", "c", "d", "e", "f", "g", "h"],
    score    = [10.0, 20.0, 30.0, 5.0, 15.0, 25.0, 35.0, 50.0],
    enrol    = [100, 200, 150, 300, 250, 100, 400, 50],
)

# Deterministic, sorted signature of a node tree: one line per pivot node as
# "depth|pivotcol=label|n=rows". Captures exactly what the CalcPivot engine
# produced (bucket/rank labels + group sizes) independent of child ordering.
function _pivot_signature(n, lines = String[])
    if !isempty(n.pivotvals)
        push!(
            lines,
            string(length(n.pivotcols), "|", n.pivotcols[end], "=",
                   n.pivotvals[end], "|n=", size(n.subdataframe, 1)),
        )
    end
    for c in n.children
        _pivot_signature(c, lines)
    end
    lines
end

function _build_signature(pivots, calcpivots)
    obj = TermWin.newTwDfTable(
        rootTwScreen, _GDF;
        pivots = pivots,
        initdepth = 4,
        aggrHints = Dict{Any,Any}(:score => :(sum(:_)), :enrol => :(sum(:_))),
        calcpivots = calcpivots,
    )
    sig = sort(_pivot_signature(obj.data.rootnode))
    TermWin.unregisterTwObj(rootTwScreen, obj)
    sig
end

session_ok = false
try
    TermWin.initsession()
    global session_ok = true
catch err
    @warn "dftable_pivot_golden.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        @testset "DfTable CalcPivot golden tree" begin
            @testset "discretize with by=region (group bucketing)" begin
                sig = _build_signature(
                    [:scoreBucket, :region],
                    Dict{Symbol,Any}(
                        :scoreBucket => dimspec(
                            :(discretize(:score, [0.0, 50.0, 100.0]));
                            by = :region,
                            kind = :pivot,
                        ),
                    ),
                )
                @test sig == [
                    "1|scoreBucket=3. [50,100)|n=8",
                    "2|region=E|n=3",
                    "2|region=N|n=1",
                    "2|region=W|n=4",
                ]
            end

            @testset "discretize row-level (empty by)" begin
                sig = _build_signature(
                    [:scoreQ],
                    Dict{Symbol,Any}(
                        :scoreQ =>
                            dimspec(:(discretize(:score, [0.0, 20.0, 40.0, 60.0]))),
                    ),
                )
                @test sig == [
                    "1|scoreQ=2. [0,20)|n=3",
                    "1|scoreQ=3. [20,40)|n=4",
                    "1|scoreQ=4. [40,60)|n=1",
                ]
            end

            @testset "topnames (classifier: name column auto-inferred as group key)" begin
                sig = _build_signature(
                    [:top2, :region],
                    Dict{Symbol,Any}(
                        :top2 => dimspec(:(topnames(:district, :score, 2))),
                    ),
                )
                @test sig == [
                    "1|top2=1. h|n=1",
                    "1|top2=2. g|n=1",
                    "1|top2=Others|n=6",
                    "2|region=E|n=3",
                    "2|region=N|n=1",
                    "2|region=W|n=1",
                    "2|region=W|n=3",
                ]
            end
        end
    finally
        TermWin.endsession()
    end
end
