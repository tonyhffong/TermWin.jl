using TermWin
using Dates

TermWin.initsession()
v = newTwCalendar2(rootTwScreen, today(), posy = :center, posx = :center)
v.title = "Pick a date (Enter=confirm, Esc=cancel)"
activateTwObj(rootTwScreen)
ret = v.value
TermWin.endsession()
println("You selected: ", string(ret))
