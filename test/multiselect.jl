using TermWin

TermWin.initsession()
arr = map( x->utf8(x), readdir() )
v = newTwMultiSelect( rootTwScreen, arr, posy=:center, posx=:center, orderable=true, substrsearch=true )
v.title = "Input: "
activateTwObj( rootTwScreen )
ret = v.value
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( "You chose ", string( ret ) )

