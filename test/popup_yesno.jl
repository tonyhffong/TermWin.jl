using TermWin

TermWin.initsession()
arr = [ "No", "Yes" ]
v = newTwPopup( rootTwScreen, arr; colorpair=12 )
v.title = "Are you sure?"
activateTwObj( rootTwScreen )
ret = v.value

v2 = newTwPopup( rootTwScreen, arr; title = "Normal confirm" )
activateTwObj( rootTwScreen )
ret2 = v2.value

TermWin.endsession()
println( "You chose      ", string( ret ) )
println( "Then You chose ", string( ret2 ) )
