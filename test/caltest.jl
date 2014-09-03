using TermWin
using Dates

TermWin.initsession()
#s = "a test"
v = newTwCalendar( rootTwScreen, today(), :random, :random )
v.title = "Input: "
activateTwObj( rootTwScreen )
ret = v.value
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( "You entered ", string( ret ) )
