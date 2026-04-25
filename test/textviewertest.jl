using TermWin
using Pkg

s = Base.read( joinpath( Pkg.dir( "TermWin" ), "src", "TermWin.jl" ), String )
tshow( s )
