using TermWin
using RDatasets
using StatsBase

#
df = dataset( "Ecdat", "Caschool" )
wmean_instruction = :( StatsBase.mean( :_, StatsBase.Weights(:EnrlTot) ) )
tshow( df;
    colorder = [ :EnrlTot, :Teachers, :Computer, :TestScr, :CompStu, "*" ],
    pivots = [ :County, :top5districts, :District ],
    initdepth = 2,
    aggrHints = Dict{Any,Any}(
        :TestScr => wmean_instruction,
        :ExpnStu => wmean_instruction,
        :CompStu => wmean_instruction,
        :Str     => wmean_instruction
        ),
    calcpivots = Dict{Symbol,Any}(
        # group-level buckets: aggregate the measure per :County, then classify the
        # counties -> a pivot dimension (non-empty `by` needs an explicit kind).
        :CountyStrBuckets => dimspec( :(discretize( :Str, [ 14,16,18,20,22,24 ], rank=true, compact=true )); by = :County, kind = :pivot ),
        :CountyTestScrBuckets => dimspec( :(discretize( :TestScr, [ 600, 620, 640, 660, 680, 700], label="score", rank=true, compact=false, reverse=true )); by = :County, kind = :pivot ),
        # row-level quantile buckets (no `by`) -> a window dimension.
        :TestScrQuantiles => dimspec( :(discretize( :TestScr, ngroups = 4 )) ),
        # topnames is a classifier verb: :District is auto-inferred as the group key.
        :top5districts => dimspec( :( topnames( :District, :TestScr, 5 ) ) )
        ),
    views = [
        Dict{Symbol,Any}( :name => "ByStr", :pivots => [ :CountyStrBuckets, :County, :District] ),
        Dict{Symbol,Any}( :name => "ByTestScr", :pivots => [ :CountyTestScrBuckets, :County, :District] ),
        Dict{Symbol,Any}( :name => "ByTestScrQtile", :pivots => [ :TestScrQuantiles, :County, :District] ),
        Dict{Symbol,Any}( :name => "Top5Schools", :pivots => [ :top5districts, :County ] )
    ],
    )
# =#

