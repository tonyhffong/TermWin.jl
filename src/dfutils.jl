#=
@doc """
Facilities to help map GUI input / expression into a function that aggregates columns.
We would store that function and use it whenever we need to aggregate a column.

Three ways to instantiate the DataFrameAggr
* Symbol. e.g. `:mean`. It's lowered into `mean(:_)`. See below for the meaning of `:_`
* Expr. e.g. `:( mean(:_,:wcol) )`, `:( quantile( :_, 0.75 ) )`
   symbols (quoted) are interpreted as the named column.
   The underscore `:_` column is special -- it's interpreted on-the-fly as the column that
   needs to be aggregated. So multiple columns can use the same expression `mean(_,:wcol)` and
   they will all use the same weight (from `wcol`), but produces target specific mean.
* Function: (most likely lambda) e.g. `df -> quantile( df[:col], 0.5 )`. It is expected
   to generate either a value (typically a scalar consistent to the column type), or
   a 1-row, 1-col dataframe.
""" ->
=#

DataFrameAggrCache = Dict{Any,Function}()

defaultAggr( ::Type{} ) = :uniqvalue
defaultAggr{T<:Real}( ::Type{T} ) = :sum
defaultAggr{T}( ::Type{Array{T,1}} ) = :unionall

function liftAggrSpecToFunc( c::Symbol, dfa::String )
    if haskey( DataFrameAggrCache, (c, dfa ) )
        return DataFrameAggrCache[ (c, dfa ) ]
    end
    ret = liftAggrSpecToFunc( c, parse( dfa ) )
    DataFrameAggrCache[ (c, dfa) ] = ret
end

function liftAggrSpecToFunc( c::Symbol, dfa::Union( Function, Symbol, Expr ) )
    if typeof( dfa ) == Function
        return dfa
    end
    if haskey( DataFrameAggrCache, (c, dfa) )
        return DataFrameAggrCache[ (c, dfa ) ]
    end
    # "mean" or "Module.aggrfunc"
    if typeof( dfa ) == Symbol || typeof( dfa ) == Expr && dfa.head == :(.) && all( x->typeof(x)==Symbol, dfa.args )
        funnameouter = gensym( "DFAggr" )
        code = :(
            function $funnameouter( _df_::AbstractDataFrame )
            end )
        push!( code.args[2].args, Expr( :call, dfa, Expr( :call, :getindex, :_df_, QuoteNode(c) ) ) )
        ret = eval( code )
    else # expr
        if !isexpr( dfa, :call )
            error( string( dfa ) * " does not look like an aggregator function")
        end
        # disallow mutating function
        fname = dfa.args[1]
        if Base.Meta.isexpr( dfa, :curly )
            error( "DataFrameAggr: curly not supported")
        elseif !( typeof( fname ) <: Symbol ) && !Base.Meta.isexpr( fname, :(.) )
            error( "DataFrameAggr: only simple function name please")
        end
        if contains( string(fname), "!" )
            error( string(fname) * " seems to have side effects" )
        end

        # replace _ with _df_[$c], and then leverage @with

        # before we do that, note that
        # (A) in DataFramesMeta, macro converts :x to Expr( :quote, :x ) but
        #     :( :x ) or parse( ":x" ) it is actually QuoteNode( :x ),
        #     so we need to do a little conversion in order to leverage that package
        function convertExpression!( ex::Expr )
            for i in 1:length( ex.args )
                a = ex.args[i]
                if typeof( a ) == QuoteNode
                    if a.value == :_
                        ex.args[i] = Expr( :quote, c )
                    else
                        ex.args[i] = Expr( :quote, a.value )
                    end
                elseif typeof( a ) == Expr
                    convertExpression!( a )
                end
            end
        end
        cdfa = deepcopy( dfa )
        convertExpression!( cdfa )

        membernames = Dict{Symbol, Symbol}()
        cdfa = DataFramesMeta.replace_syms(cdfa, membernames)
        funargs = map(x -> :( getindex( _df_, $(Meta.quot(x))) ), collect(keys(membernames)))
        funnameouter = gensym("DFAggr")
        funname = gensym()
        code = quote
            function $funnameouter( _df_::AbstractDataFrame )
                function $funname($(collect(values(membernames))...))
                    $cdfa
                end
                $funname($(funargs...))
            end
        end
        ret = eval( code )
    end
    DataFrameAggrCache[ (c, dfa) ] = ret
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
    lvls = DataArrays.levels(x)
    if skipna
        l = dropna( lvls )
        if length(l) == 1
            return l[1]
        end
        return NA
    end
    if length(lvls) == 1
        return lvls[1]
    end
    return NA
end

function uniqvalue{T<:String}( x::Union( Array{T}, DataArray{T}, PooledDataArray{T} ); skipna::Bool=true, skipempty::Bool=true )
    lvls = DataArrays.levels(x)
    if skipna
        l = dropna( lvls )
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
        emptyidx = findfirst( lvls, "" )
        if length( lvls ) == 1 && emptyidx == 0
            return lvls[1] # could be NA
        elseif length( lvls ) == 2 && emptyidx != 0
            if emptyidx == 1
                return lvls[2]
            else
                return lvls[1]
            end
        end
    elseif length( lvls ) == 1
        return lvls[1]
    end
    return NA
end

type DataFrameCalcPivot
    f::Function
    sig::Any
    by::Array{Symbol,1}
end
