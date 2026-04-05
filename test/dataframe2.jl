using TermWin
using RDatasets
df = dataset( "HistData", "Jevons" )
tshow( df;
    aggrHints = Dict{Any,Any}(
    :Actual=> "mean",
    :Estimated=> "mean",
    :Error => "mean"
    ) )
# =#
