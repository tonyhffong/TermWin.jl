using TermWin

# a simple diagnostic tool to help find out what happens when user drag the title edge around.
# save the log into debug.log

# Wipe any old log and start fresh
logpath = joinpath(pkgdir(TermWin), "debug.log")
isfile(logpath) && rm(logpath)
TermWin.logstart()

TermWin.initsession()
arr = map(x->string(x), readdir())
v = newTwMultiSelect(rootTwScreen, arr, posy=:center, posx=:center,
                     orderable=true, substrsearch=true)
v.title = "DRAG ME by my top border"
activateTwObj(rootTwScreen)
ret = v.value
TermWin.endsession()
println("You chose ", string(ret))
println("\nLog written to: ", logpath)
