using TermWin
using RDatasets
using Compat
df = dataset( "HistData", "Jevons" )
tshow( df;
    aggrHints = @compat(Dict{Any,DataFrameAggr}(
    :Actual=> DataFrameAggr( "mean" ),
    :Estimated=> DataFrameAggr( "mean" ),
    :Error => DataFrameAggr( "mean" )
    ) ) )
# =#
