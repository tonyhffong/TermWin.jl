# test uniqvalue, unionall, discretize, topnames
using TermWin
using DataArrays
using Base.Test

@test isna( uniqvalue( @data( [ 1,2,3 ] ) ) )
@test uniqvalue( @data( [ 2,2,2 ] ) ) == 2
@test uniqvalue( @data( [ 2,2,NA ] ) ) == 2
@test isna( uniqvalue( @data( [ ] ) ) )

@test isna( uniqvalue( @data( [ "","",NA ] ) ) )
@test uniqvalue( @data( [ "a","a", "", NA ] ) ) == "a"
@test isna( uniqvalue( @data( [ "a","b", "", NA ] ) ) )

arr = unionall( @data( Array[ [1], [2,3] ] ) )
sort!( arr )
@test arr == [1,2,3]
arr = DataArray( Array{Int,1}[ Int[1], Int[2,3] ] )
push!(arr, NA)
arr = unionall(arr)
sort!(arr)
@test arr == [1,2,3]

arr = @data( [ 1,2,3, NA] )
result = discretize( arr, [ 0,1,2,3])
@test result[1] == "3. 1"
@test result[2] == "4. 2"
@test result[3] == "5. 3+"
@test isna( result[4] )

arr = @data( [ -1.0, 1.0,2.0,3.0, NA] )
result = discretize( arr, [ 0,1,2,3])
@test result[1] == "1. <0"
@test result[2] == "3. [1,2)"
@test result[3] == "4. [2,3)"
@test result[4] == "5. ≥3"
@test isna( result[5] )

arr = @data( [ -1.0, 1.0,2.0,3.0, NA] )
result = discretize( arr, [ 0,1,2,3], label="x")
@test result[1] == "1. x < 0"
@test result[2] == "3. 1 ≤ x < 2"
@test result[3] == "4. 2 ≤ x < 3"
@test result[4] == "5. 3 ≤ x"
@test isna( result[5] )

arr = @data( [ -1.0, 1.0,2.0,3.0, NA] )
result = discretize( arr, [ 0,1,2,3], label="x", absolute=true)
@test result[1] == "3. 1 ≤ |x| < 2"
@test result[2] == "3. 1 ≤ |x| < 2"
@test result[3] == "4. 2 ≤ |x| < 3"
@test result[4] == "5. 3 ≤ |x|"
@test isna( result[5] )

name=@data( [ "Alice", "Bob", "Jane", "Joe" ] )
score=@data( [ 7, 8, 9, 5 ] )
result = topnames( name, score, 2 )
@test result[ 1 ] == "Others"
@test result[ 2 ] == "2. Bob"
@test result[ 3 ] == "1. Jane"
@test result[ 4 ] == "Others"

name=@data( [ "Alice", "Bob", "Jane", "Joe" ] )
score=@data( [ 7, 9, 9, 5 ] )
result = topnames( name, score, 2 )
@test result[ 1 ] == "2. Alice"
@test result[ 2 ] == "1. Bob"
@test result[ 3 ] == "1. Jane"
@test result[ 4 ] == "Others"

# Note that in actual usage "name" is always sorted
# see CalcPivot constructor's handling of topnames' "by" argument
name=@data( [ "Alice", "Bob", "Jane", "Joe" ] )
score=@data( [ 7, 9, 9, 5 ] )
result = topnames( name, score, 2, dense=false )
@test result[ 1 ] == "Others" # Alice would have been 3rd
@test result[ 2 ] == "1. Bob"
@test result[ 3 ] == "1. Jane"
@test result[ 4 ] == "Others"
