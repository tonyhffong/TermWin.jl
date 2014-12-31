using TermWin

TermWin.initsession()
arr = readdir()
#s = "a test"
v = newTwPopup( rootTwScreen, arr, substrsearch=true )
v.title = "Input: "
activateTwObj( rootTwScreen )
ret = v.value
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( "You chose ", string( ret ) )

