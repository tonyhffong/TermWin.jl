using TermWin

TermWin.logstart()
TermWin.initsession()
#s = "a test"
v = newTwList( rootTwScreen; height=25, width=80, posy = :random, posx = :random, box=true, horizontal=true )
v1 = newTwList( v; height=25,width=80, box=true)
a = newTwEntry( v1, Rational{Int}; width=25, title="test1", box=false )
a.value = 0
a = newTwEntry( v1, Rational{Int}; width=25, title="test2", box=false )
a.value = 1

v2 = newTwList( v; height=25,width=80, box=true)
a = newTwEntry( v2, UTF8String; width=25, title="test3", box=false )
a.value = "test"
a = newTwEntry( v2, Int; width=25, title="test4", box=false )
a.value = 1

activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
