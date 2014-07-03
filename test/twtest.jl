using TermWin

TermWin.initsession()
s = open( readall, "TermWin.jl" )
#s = "a test"
scr = newTwScreen( TermWin.rootwin )
v = newTwViewer( scr, s, :center, :center, bottomText = "F1: Help  Esc: Exit", trackLine=true )
activateTwObj( scr )
scr = nothing
v = nothing
gc()
TermWin.endsession()

