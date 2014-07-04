using TermWin

TermWin.initsession()
#s = "a test"
v = newTwEntry( rootTwScreen, Rational{Int}, 25, :center, :center, showHelp=true, box=true )
v.title = "Input: "
v.data.tickSize = 1
#ret = activateTwObj( v )
activateTwObj( scr )
unregisterTwObj( scr, v )
v = nothing
v = newTwEntry( scr, String, 30, 0.3, 0.3 )
v.title = "String: "
activateTwObj( scr )
unregisterTwObj( scr, v )
ret = v.value
v = nothing
TermWin.endsession()
println( "You entered ", string( ret ) )
