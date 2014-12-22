using TermWin
using Base.Test

@test TermWin.substr_by_width( "abc", 0, 3 ) == "abc"
@test TermWin.substr_by_width( "abc", 0, 1 ) == "a"
@test TermWin.substr_by_width( "abc", 0, -1 ) == "abc"
@test TermWin.substr_by_width( "abc", 1, -1 ) == "bc"
@test TermWin.substr_by_width( "abc", 2, -1 ) == "c"
@test TermWin.substr_by_width( "abc", 3, -1 ) == ""
@test TermWin.substr_by_width( "abc", 3, 1 ) == ""
@test TermWin.substr_by_width( "abc", 2, 1 ) == "c"

# test decorators
ohat = "o" * string( '\U302' )
ahat = "a" * string( '\U302' )
ehat = "e" * string( '\U302' )
str = ohat * ahat * ehat
@test length(str)==6
@test TermWin.substr_by_width( str, 0, 3 ) == str
@test TermWin.substr_by_width( str, 0, 1 ) == ohat
@test TermWin.substr_by_width( str, 0, -1 ) == str
@test TermWin.substr_by_width( str, 1, -1 ) == ahat * ehat
@test TermWin.substr_by_width( str, 2, -1 ) == ehat
@test TermWin.substr_by_width( str, 3, 1 ) == ""
@test TermWin.substr_by_width( str, 3, 1 ) == ""
@test TermWin.substr_by_width( str, 2, 1 ) == ehat

@test TermWin.insertstring( str, "a", 1, false ) == "a" * str
@test TermWin.insertstring( str, "a", 1, true ) == "a" * ahat * ehat
@test TermWin.insertstring( str, "a", 2, false ) == ohat * "a" * ahat * ehat
@test TermWin.insertstring( str, "a", 2, true ) == ohat * "a" * ehat
@test TermWin.insertstring( str, "a", 3, false ) == ohat * ahat * "a" * ehat
@test TermWin.insertstring( str, "a", 3, true ) == ohat * ahat * "a"

@test TermWin.delete_char_at( str, 1 ) == ahat * ehat
@test TermWin.delete_char_at( str, 2 ) == ohat * ehat
@test TermWin.delete_char_at( str, 3 ) == ohat * ahat

@test TermWin.delete_char_before( "abc", 1 ) == ("abc",1)
@test TermWin.delete_char_before( "abc", 2 ) == ("bc",1)
@test TermWin.delete_char_before( "abc", 3 ) == ("ac",2)
@test TermWin.delete_char_before( "abc", 4 ) == ("ab",3)

@test TermWin.delete_char_before( str, 1 ) == (str,1)
@test TermWin.delete_char_before( str, 2 ) == ("o" * ahat * ehat,2)
@test TermWin.delete_char_before( str, 3 ) == (ohat * "a" * ehat,3)
@test TermWin.delete_char_before( str, 4 ) == (ohat * ahat * "e",4)
