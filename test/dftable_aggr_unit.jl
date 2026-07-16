# Headless test for runtime per-column aggregation overrides (the `a` binding).
#
# A DfTable user can type an aggregation spec for the column under the cursor; it
# is parsed by the UNTRUSTED safe grammar (parseaggr -- no eval, `_` is the column
# being aggregated) and stored on that column's colInfo. This drives the
# underlying `_dt_set_aggr!` directly (not the TTY entry) and asserts the
# recomputed aggregate, the blank-reverts-to-default behaviour, and the safety
# rejections.
#
# Run:  julia --project=. test/dftable_aggr_unit.jl

using Test
using TermWin, DataFrames

const _ADF = DataFrame(
    region = ["E", "E", "W", "W", "N"],
    score  = [10.0, 20.0, 5.0, 35.0, 50.0],
    wt     = [1.0, 3.0, 2.0, 2.0, 1.0],
)

session_ok = false
try
    TermWin.initsession()
    global session_ok = true
catch err
    @warn "dftable_aggr_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        @testset "DfTable per-column aggregation override (safe grammar)" begin
            @testset "`_` target and named-column specs recompute the aggregate" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _ADF)

                TermWin._dt_set_aggr!(obj, :score, "maximum(_)")
                @test obj.data.rootnode[:score] == 50.0
                TermWin._dt_set_aggr!(obj, :score, "minimum(_)")
                @test obj.data.rootnode[:score] == 5.0

                # reference sibling columns by name: weighted mean of score by wt
                TermWin._dt_set_aggr!(obj, :score, "sum(_ * wt) / sum(wt)")
                @test obj.data.rootnode[:score] ≈
                    sum(_ADF.score .* _ADF.wt) / sum(_ADF.wt)

                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "blank spec reverts to the resolved default" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _ADF;
                    aggrHints = Dict{Any,Any}(:score => :(sum(:_))))
                @test obj.data.rootnode[:score] == sum(_ADF.score)   # the hinted default

                TermWin._dt_set_aggr!(obj, :score, "mean(_)")
                @test obj.data.rootnode[:score] ≈ sum(_ADF.score) / length(_ADF.score)

                TermWin._dt_set_aggr!(obj, :score, "   ")             # blank -> revert
                @test obj.data.rootnode[:score] == sum(_ADF.score)

                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "override survives a pivot tree and invalidates child caches" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _ADF; pivots = [:region])
                TermWin._dt_rebuild_tree!(obj)
                TermWin._dt_set_aggr!(obj, :score, "maximum(_)")
                # E-node max is 20 (10,20); the child cache was invalidated
                enode = first(filter(n -> n.pivotvals == ("E",),
                                     obj.data.rootnode.children))
                @test enode[:score] == 20.0
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end

            @testset "safety: invalid / eval-shaped specs are rejected" begin
                obj = TermWin.newTwDfTable(rootTwScreen, _ADF)
                @test_throws Exception TermWin._dt_set_aggr!(obj, :score, "maen(_)")      # typo op
                @test_throws Exception TermWin._dt_set_aggr!(obj, :score, "sum(nosuch)")  # unknown col
                @test_throws Exception TermWin._dt_set_aggr!(obj, :score, "Base.run(`ls`)")
                @test_throws Exception TermWin._dt_set_aggr!(obj, :nope, "sum(_)")        # unknown column
                TermWin.unregisterTwObj(rootTwScreen, obj)
            end
        end
    finally
        TermWin.endsession()
    end
end

println("dftable_aggr_unit.jl: done.")
