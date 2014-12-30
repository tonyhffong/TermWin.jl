using TermWin

TermWin.logstart()
TermWin.initsession()
#s = "a test"
v1 = newTwList( rootTwScreen, 25,80, :random, :random; box=true )
a = newTwEntry( rootTwScreen, Rational{Int}, 25, :random, :random, title="test1" )
a.value = 0
push_widget!( v1, a )
a = newTwEntry( rootTwScreen, Rational{Int}, 25, :random, :random, title="test2" )
a.value = 1
push_widget!( v1, a )

v2 = newTwList( rootTwScreen, 25,80, :random, :random; box=true )
a = newTwEntry( rootTwScreen, UTF8String, 25, :random, :random, title="test3" )
a.value = "test"
push_widget!( v2, a )
a = newTwEntry( rootTwScreen, Int, 25, :random, :random, title="test4" )
a.value = 1
push_widget!( v2, a )

v = newTwList( rootTwScreen, 25, 80, :random, :random; box=true, horizontal=true )
push_widget!( v, v1 )
push_widget!( v, v2 )

activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
