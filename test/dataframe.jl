using TermWin
using RDatasets
using Compat
# #=
df = dataset( "Ecdat", "Caschool" )
tshow( df;
    colorder = [ :EnrlTot, :Teachers, :Computer, :TestScr, :CompStu, "*" ],
    pivots = [ :CountyTestScrBuckets, :County, :District ],
    initdepth = 2,
    aggrHints = @compat(Dict{Any,Any}(
        :TestScr => :( mean( :_, weights(:EnrlTot) ) ),
        :ExpnStu => :( mean( :_, weights(:EnrlTot) ) ),
        :CompStu => :( mean( :_, weights(:EnrlTot) ) ),
        :Str     => :( mean( :_, weights(:EnrlTot) ) )
        ) ),
    calcpivots = @compat( Dict{Symbol,Any}(
        :CountyStrBuckets => CalcPivot( :(discretize( :Str, [ 14,16,18,20,22,24 ], rank=true, compact=true )), by=[ :County ] ),
        :CountyTestScrBuckets => CalcPivot( :(discretize( :TestScr, [ 600, 620, 640, 660, 680, 700], label="score", rank=true, compact=false, reverse=true )), by=[ :County ] )
        ) ),
    views = [
        @compat(Dict{Symbol,Any}( :name => "ByStr", :pivots => [ :CountyStrBuckets, :County, :District] ) )
    ],
    )
# =#

