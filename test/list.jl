using TermWin

TermWin.logstart()
TermWin.initsession()
#s = "a test"
v = newTwList( rootTwScreen, 25,80, :random, :random; box=true )
v.title = "Input: "
a = newTwEntry( rootTwScreen, Rational{Int}, 25, :random, :random, title="test1" )
a.value = 0
push_widget!( v, a )
a = newTwEntry( rootTwScreen, Rational{Int}, 25, :random, :random, title="test2" )
a.value = 1
push_widget!( v, a )
activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
