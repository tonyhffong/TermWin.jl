using TermWin

TermWin.initsession()
v = newTwFileBrowser( rootTwScreen )
activateTwObj( rootTwScreen )
ret = v.value
TermWin.endsession()
println( "You entered ", string( ret ) )
