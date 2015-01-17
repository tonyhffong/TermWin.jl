using TermWin
if VERSION < v"0.4-"
    using Dates
else
    using Base.Dates
end

#TermWin.logstart()
TermWin.initsession()
#s = "a test"
v = newTwList( rootTwScreen; height=25, width=80, posy = :random, posx = :random, box=true, horizontal=true )
v1 = newTwList( v; height=25,width=80)
for i = 1:12
    a = newTwEntry( v1, Float64; width=30, title=@sprintf("float %2d", i), box=true)
    a.data.inputText = "0"
    a.value = 0
end

v2 = newTwList( v; height=25,width=80)
for i = 1:7
    a = newTwEntry( v2, UTF8String; width=30, title=@sprintf("string %2d",i), box=true)
    a.data.inputText = "abcdefghijk"
    a.value = "abcdefghijk"
end

v3 = newTwList( v )
for i=1:10
    a = newTwEntry( v3, Int; width=30, title=@sprintf("integer %2d",i), box=true)
    a.data.inputText = "1"
    a.value = 1
end
TermWin.update_list_canvas( v )

tshow( v )
#activateTwObj( rootTwScreen )
#unregisterTwObj( rootTwScreen, v )
#TermWin.endsession()
println( v )
