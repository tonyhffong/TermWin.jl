using TermWin
if VERSION < v"0.4-"
    using Dates
else
    using Base.Dates
end

TermWin.logstart()
TermWin.initsession()
#s = "a test"
v = newTwList( rootTwScreen; height=25, width=80, posy = :random, posx = :random, box=true, horizontal=true )
v1 = newTwList( v; height=25,width=80, box=true)
a = newTwEntry( v1, Rational{Int}; width=20, title="decimal ", box=true)
a.data.inputText = "0"
a.value = 0
a = newTwEntry( v1, Float64;       width=20, title="float   ", box=true)
a.data.inputText = "1.0"
a.value = 1.0
a = newTwEntry( v1, Date;          width=20, title="date  ", box=true)
a.value = today()
a.data.inputText = string( today() )

v2 = newTwList( v; height=25,width=80, box=true)
a = newTwEntry( v2, UTF8String; width=20, title="string  ", box=true)
a.data.inputText = "abcdefghijk"
a.value = "abcdefghijk"
a = newTwEntry( v2, Int;        width=20, title="integer ", box=true)
a.value = 1

activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
TermWin.endsession()
println( v )
