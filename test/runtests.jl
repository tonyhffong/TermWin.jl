using TermWin
using Base.Test

# write your own tests here
using Lint

msgs = lintpkg( "TermWin", returnMsgs = true )
println( msgs )
sumseverity = 0
if !isempty( msgs )
    sumseverity = sum( x->x.level, msgs )
end
@test sumseverity == 0

include( "dftests.jl" )
include( "strtests.jl" )
