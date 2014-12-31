using TermWin

TermWin.logstart()
TermWin.initsession()
#s = "a test"
v1 = newTwList( rootTwScreen; height=25,width=80, box=true )
a = newTwEntry( rootTwScreen, Rational{Int}; width=25, title="test1" )
a.value = 0
push_widget!( v1, a )
a = newTwEntry( rootTwScreen, Rational{Int}; width=25, title="test2" )
a.value = 1
push_widget!( v1, a )

v2 = newTwList( rootTwScreen; height=25,width=80, box=true )
a = newTwEntry( rootTwScreen, UTF8String; width=25, title="test3" )
a.value = "test"
push_widget!( v2, a )
a = newTwEntry( rootTwScreen, Int; width=25, title="test4" )
a.value = 1
push_widget!( v2, a )

v = newTwList( rootTwScreen; height=25, width=80, posy = :random, posx = :random, box=true, horizontal=true )
push_widget!( v, v1 )
push_widget!( v, v2 )

activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
