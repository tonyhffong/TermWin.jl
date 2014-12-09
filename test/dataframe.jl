using TermWin
using RDatasets
using Compat
# #=
df = dataset( "Ecdat", "BudgetFood" )
tshow( df;
    colorder = [ :Sex, :Age, :WFood, "*", :Town ],
    pivots = [ :Town, :Sex ],
    aggrHints = @compat(Dict{Any,Any}(
    :TotExp => "mean",
    :Age => "mean",
    :WFood => "mean",
    :Town => "uniqvalue"
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
