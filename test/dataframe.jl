using TermWin
using RDatasets
using Compat
# #=
df = dataset( "Ecdat", "BudgetFood" )
tshow( df;
    colorder = [ :Sex, :Age, :WFood, "*", :Town ],
    pivots = [ :Town, :Sex ],
    aggrHints = @compat(Dict{Any,DataFrameAggr}(
    :TotExp => DataFrameAggr( "mean" ),
    :Age => DataFrameAggr( "mean" ),
    :WFood => DataFrameAggr( "mean" ),
    :Town => DataFrameAggr( "uniqvalue" )
    ) ) )
# =#

#=
df = dataset( "HistData", "Jevons" )
tshow( df;
    aggrHints = @compat(Dict{Any,DataFrameAggr}(
    :Actual=> DataFrameAggr( "mean" ),
    :Estimated=> DataFrameAggr( "mean" ),
    :Error => DataFrameAggr( "mean" )
    ) ) )
# =#
