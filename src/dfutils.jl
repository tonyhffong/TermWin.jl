#=
@doc """
Facilities to help map GUI input / expression into a function that aggregates columns.
We would store that function and use it whenever we need to aggregate a column.

Three ways to instantiate the DataFrameAggr
* String: either a simple name "mean", or an expression wmean( :col, :WeightColumn )
* Similarly, Symbol or expression, such as :mean, or :( wmean( :col, :WeightColumn ) )
    * if just a simple name, it is assumed to be a function, we would try these signature
        * f( x::DataArray ) -> output is the aggregated scalar
        * f( x::Dataframe ) -> output is the aggregated scalar, rare.
    * if expression, it must be of the form
        * f( args..., kw1=v1, kw2=v2, ... )
        * straightforward symbols are expected to be column names
""" ->
=#
immutable DataFrameAggr
    f::Function
    sig::Any
end

DataFrameAggrCache = Dict{Any, DataFrameAggr}()

DataFrameAggr() = DataFrameAggr( _->NA, (DataArray,) )

function DataFrameAggr( x::String )
    global DataFrameAggrCache
    if haskey( DataFrameAggrCache, x )
        return DataFrameAggrCache[ x ]
    end
    ex = parse( x )
    ret = DataFrameAggr( ex )
    DataFrameAggrCache[x] = ret
    ret
end

function DataFrameAggr( ex::Union( Expr, Symbol ) )
    global DataFrameAggrCache
    if haskey( DataFrameAggrCache, ex )
        return DataFrameAggrCache[ ex ]
    end

    if typeof( ex ) == Symbol
        # assume it is a function, e.g. mean, std, uniq, countuniq, etc.
        if contains( string(ex), "!" )
            error( string(ex) * " seems to have side effects" )
        end
        if ex == :NA
            return ( DataFrameAggrCache[ex] = DataFrameAggr() )
        end
        v = nothing
        try
            v = eval( Main, ex )
        end
        if typeof( v ) != Function
            error( string( ex ) * " does not represent a function" )
        end
        ex = :( $ex() )
    else
        if !isexpr( ex, :call )
            error( string( ex ) * " does not look like an aggregator function")
        end
        # disallow mutating function
        fname = ex.args[1]
        if Base.Meta.isexpr( fname, :curly )
            error( "DataFrameAggr: curly not supported")
        elseif !( typeof( fname ) <: Symbol )
            error( "DataFrameAggr: only simple function name please")
        end
        if contains( string(fname), "!" )
            error( string(fname) * " seems to have side effects" )
        end
        v = nothing
        try
            v = eval( Main, fname )
        end
        if typeof( v ) != Function
            error( string( fname ) * " does not represent a function" )
        end
    end

    mt = methods( v )
    for m in mt
        if isempty( m.sig )
            continue
        end
        # count the non-kw signatures
        nargs = 0
        for i = 2:length( ex.args )
            if !isexpr( ex.args[i], [ :parameters, :kw ] )
                nargs += 1
            end
        end
        if typeof( m.sig[1] ) <: Tuple
            continue
        end
        if typeof( m.sig[1] ) <: UnionType
            continue
        end
        if in( m.sig[1].name.name, [ :DataArray, :PooledDataArray, :AbstractDataArray ] ) && nargs == 0
            ex2 = deepcopy( ex )
            insert!( ex2.args, 2, :_ )
            l = eval( Main,Expr( :(->), :_, ex2 ) )
            return ( DataFrameAggrCache[ex] = DataFrameAggr( l, (DataArray,) ) )
        elseif in( m.sig[1].name.name,[:DataFrame, :AbstractDataFrame] )
            ex2 = deepcopy( ex )
            insert!( ex2.args, 2, :_ )
            l = eval( Main,Expr( :(->), :_, ex2 ) )
            return ( DataFrameAggrCache[ex] = DataFrameAggr( l, (DataFrame,) ) )
        end
    end
    error( string( v ) * ": No usable method. Accepts (DataArray/PDA,) or (DataFrame,args...)" )
end

function DataFrameAggr( ::Type{} )
    DataFrameAggr( "uniqvalue" )
end

function DataFrameAggr{T<:Real}( ::Type{T} )
    DataFrameAggr( "sum" )
end

function DataFrameAggr{T}( ::Type{Array{T,1}} )
    DataFrameAggr( "unionall" )
end

function unionall( x::AbstractDataArray )
    l = dropna( x )
    t = eltype( eltype( x ) )
    s = Set{t}()
    for el in l
        push!( s, el... )
    end
    collect( s )
end

function unionall( x::Array )
    t = eltype( eltype( x ) )
    s = Set{t}()
    for el in x
        push!( s, el... )
    end
    collect( s )
end

function uniqvalue( x::AbstractDataArray; skipna::Bool=true )
    levels = DataArrays.levels(x)
    if skipna
        l = dropna( levels )
        if length(l) == 1
            return l[1]
        end
        return NA
    end
    if length(levels) == 1
        return levels[1]
    end
    return NA
end

function uniqvalue{T<:String}( x::Union( Array{T}, DataArray{T}, PooledDataArray{T} ); skipna::Bool=true, skipempty::Bool=true )
    levels = DataArrays.levels(x)
    if skipna
        l = dropna( levels )
        if skipempty
            emptyidx = findfirst( l, "" )
            if length( l ) == 1 && emptyidx == 0
                return l[1]
            elseif length( l ) == 2 && emptyidx != 0
                if emptyidx == 1
                    return l[2]
                else
                    return l[1]
                end
            end
        elseif length( l ) == 1
            return l[1]
        end
        return NA
    end
    if skipempty
        emptyidx = findfirst( levels, "" )
        if length( levels ) == 1 && emptyidx == 0
            return levels[1] # could be NA
        elseif length( levels ) == 2 && emptyidx != 0
            if emptyidx == 1
                return levels[2]
            else
                return levels[1]
            end
        end
    elseif length( levels ) == 1
        return levels[1]
    end
    return NA
end
