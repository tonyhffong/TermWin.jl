using TermWin

TermWin.initsession()
TermWin.logstart()
arr = readdir()
#s = "a test"
v = newTwPopup( rootTwScreen, arr; sortmatched =true )
v.title = "Input: "
activateTwObj( rootTwScreen )
ret = v.value
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( "You chose ", string( ret ) )

