using TermWin
using RDatasets
using Compat
# #=
df = dataset( "Ecdat", "Caschool" )
wmean_instruction = :( mean( :_, weights( :EnrlTot ) ) )
tshow( df;
    colorder = [ :EnrlTot, :Teachers, :Computer, :TestScr, :CompStu, "*" ],
    pivots = [ :County, :top5districts, :District ],
    initdepth = 2,
    aggrHints = @compat(Dict{Any,Any}(
        :TestScr => wmean_instruction,
        :ExpnStu => wmean_instruction,
        :CompStu => wmean_instruction,
        :Str     => wmean_instruction
        ) ),
    calcpivots = @compat( Dict{Symbol,Any}(
        :CountyStrBuckets => CalcPivot( :(discretize( :Str, [ 14,16,18,20,22,24 ], rank=true, compact=true )), :County ),
        :CountyTestScrBuckets => CalcPivot( :(discretize( :TestScr, [ 600, 620, 640, 660, 680, 700], label="score", rank=true, compact=false, reverse=true )), :County ),
        :TestScrQuantiles => CalcPivot( :(discretize( :TestScr, ngroups = 4 )) ),
        :top5districts => CalcPivot( :( topnames( :District, :TestScr, 5 ) ) )
        ) ),
    views = [
        @compat(Dict{Symbol,Any}( :name => "ByStr", :pivots => [ :CountyStrBuckets, :County, :District] ) ),
        @compat(Dict{Symbol,Any}( :name => "ByTestScr", :pivots => [ :CountyTestScrBuckets, :County, :District] ) ),
        @compat(Dict{Symbol,Any}( :name => "ByTestScrQtile", :pivots => [ :TestScrQuantiles, :County, :District] ) ),
        @compat(Dict{Symbol,Any}( :name => "Top5Schools", :pivots => [ :top5districts, :County ] ) )
    ],
    )
# =#

