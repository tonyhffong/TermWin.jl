using TermWin

TermWin.initsession()
arr = [ "No", "Yes" ]
v = newTwPopup( rootTwScreen, arr )
v.title = "Are you sure?"
activateTwObj( rootTwScreen )
ret = v.value
TermWin.endsession()
println( "You chose ", string( ret ) )
