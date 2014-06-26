using TermWin
using Base.Test

# write your own tests here
using Lint

@test isempty( lintpkg( "TermWin", returnMsgs = true ) )
