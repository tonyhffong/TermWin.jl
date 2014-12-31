using TermWin
using Dates

TermWin.initsession()
#s = "a test"
v = newTwEntry( rootTwScreen, Date; width=25, posy=:center, posx=:center, showHelp=true, box=true )
v.title = "Date: "
v.data.tickSize = 1
activateTwObj( rootTwScreen )
ret = v.value
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( "You entered ", string( ret ) )
