using TermWin
TermWin.initsession()
v = nothing
v = newTwEntry( rootTwScreen, String; width=30, posy=:random, posx=:random )
v.title = "String: "
activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
ret = v.value
v = nothing
TermWin.endsession()
println( "You entered ", string( ret ) )
