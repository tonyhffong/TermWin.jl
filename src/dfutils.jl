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
        if !Base.Meta.isexpr( dfa, :call )
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
        cdfa = deepcopy( dfa )
        convertExpression!( cdfa, c )

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

# used by aggregation lifting and calcpivot lifting
function convertExpression!( ex::Expr, column_ctx::Symbol = symbol("") )
    for i in 1:length( ex.args )
        a = ex.args[i]
        if typeof( a ) == QuoteNode
            if a.value == :_ && column_ctx != symbol("")
                ex.args[i] = Expr( :quote, column_ctx )
            else
                ex.args[i] = Expr( :quote, a.value )
            end
        elseif typeof( a ) == Expr
            convertExpression!( a )
        end
    end
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

immutable CalcPivot
    spec::Any
    by::Array{Symbol,1}
    CalcPivot( x; by=Symbol[] ) = new( x, by )
end

CalcPivotFuncCache = Dict{ Any, Function }()
CalcPivotAggrDepCache = Dict{ Any, Array{Symbol,1} }()

# CalcPivot is a more complicated beast compared to aggregation.
# CalcPivot is always a function call. It makes no sense to have
# a default column. It is always generated from some existing column(s)
function liftCalcPivotToFunc( cp::CalcPivot )
    liftCalcPivotToFunc( cp.spec, cp.by )
end

function liftCalcPivotToFunc( cpspec::Union(String,Expr), by::Array{Symbol,1} )
    if haskey( CalcPivotFuncCache, (cpspec, by ) )
        return CalcPivotFuncCache[ (cpspec, by ) ]
    end
    if typeof( cpspec ) <: String
        ex = parse( cpspec )
    else
        ex = cpspec
    end

    if !Base.Meta.isexpr( ex, :call )
        error( string( ex ) * " does not look like an aggregator function")
    end
    # disallow mutating function
    fname = ex.args[1]
    if Base.Meta.isexpr( ex, :curly )
        error( "CalcPivot: curly not supported")
    elseif !( typeof( fname ) <: Symbol ) && !Base.Meta.isexpr( fname, :(.) )
        error( "CalcPivot: only simple function name please")
    end
    if contains( string(fname), "!" )
        error( string(fname) * " seems to have side effects" )
    end
    cex = deepcopy( ex )
    convertExpression!( cex )
    funnameouter = gensym("calcpvt")
    funname = gensym()

    membernames = Dict{Symbol, Symbol}()
    cex = DataFramesMeta.replace_syms(cex, membernames)
    # keys are the columns. values are the unique gensyms

    if !isempty( by )
        funargs = map(x -> :( getindex( byf, $(Meta.quot(x))) ), collect(keys(membernames)))
        aggregates = setdiff( collect( keys( membernames ) ), by )
        CalcPivotAggrDepCache[ (cpspec, by ) ] = aggregates
        aggr_args = Any[]
        lambdasym = gensym( "lambdadf" )
        for a in aggregates
            # basically we want to do
            # byf = by(_df_, by, lambdadf -> DataFrame(b = aggrfuncs[:b](lambdadf), c = aggrfuncs[:c](lambdadf), ... )
            push!( aggr_args, Expr( :kw, a, Expr( :call, Expr( :ref, :aggrfuncs, QuoteNode( a ) ), lambdasym ) ) )
        end

        bycolsexpr=Expr( :vcat, map( _->QuoteNode(_), by )... ) # [ :a, :b, :c ... ]
        #bycolsexpr=Expr( :vcat, by... ) # [ :a, :b, :c ... ]
        aggrcode = Expr( :->, lambdasym, Expr( :call, DataFrame, aggr_args... ) )
        code = :(
            function $funnameouter( _df_::AbstractDataFrame, c::Symbol; kwargs... ) # we need kwargs here for aggregate specs
                aggrfuncs = Dict{Symbol,Function}()
                for (aggrc,spec) in kwargs
                    # this would throw if spec is not compliant, as usual
                    aggrfuncs[aggrc] = TermWin.liftAggrSpecToFunc(aggrc, spec )
                end
                # if kwargs doesn't have the required columns, it'll throw in this line
                byf = DataFrames.by( _df_, $bycolsexpr, $aggrcode )
                function $funname($(collect(values(membernames))...))
                    $cex
                end
                vals = $funname($(funargs...))
                ret = byf[ $bycolsexpr ]
                ret[ c ] = vals
                ret # This has all the "by" columns and the result, named by c
                # joining is done elsewhere
            end
        )
    else # much simplier, we are doing line-by-line calculation.
        # Common use case: a simple bucketing, or a line by line ranking.
        # a "pure" reading on empty "by" array may mean we aggregate everything in the
        # dataframe into one row, and then attach this row's value (a constant) into every row.
        # I wonder if there's a legitimate use case for this.
        CalcPivotAggrDepCache[ (cpspec, by )] = Symbol[]
        funargs = map(x -> :( getindex( _df_, $(Meta.quot(x))) ), collect(keys(membernames)))
        code = :(
            function $funnameouter( _df_::AbstractDataFrame ) # we need kwargs here for aggregate specs
                function $funname($(collect(values(membernames))...))
                    $cex
                end
                $funname($(funargs...))
                # the creation of column is done elsewhere
            end
        )
    end
    ret = eval( code )
    CalcPivotFuncCache[ (cpspec, by ) ] = ret
end

# useful CalcPivot examples
# discretize( :measure, label="x", leftequal=true, abs=false, rank=true, compact=true,
#     reverse=false,
#     prefix="$", suffix="m", formatscale=1e-6, log=false, ... )
# topnames( :name, :measure, 3, abs=false )
# boolpivot( :measure .> 0, true_str = "measure > 0" )

function discretize{S<:Real, T<:Real}(x::AbstractArray{S,1}, breaks::Vector{T};
    leftequal=true, # t1 <= x < t2 or t1 < x <= t2?
    absolute=false, # t1 <= |x| < t2?
    rank=true, # add a rank to the string output for easier sorting?
    ranksep = ". ", # "1. t1 <= x < t2"?
    compact=true, # <t1, [t1,t2), t2+. Further shortened for integer intervals
    reverse=false, # reverse the rank from the largest first?
    label = "", # if not compact, what label do we use for x?
    # the following format the boundary numbers
    # see Formatting.jl
    prefix="", suffix="", scale=1, precision=-1,
    commas=false,stripzeros=(precision==-1),parens=false,
    mixedfraction=false,autoscale=:none,conversion=""
    )
    if !issorted(breaks)
        sort!(breaks)
    end
    min_x, max_x = minimum(x), maximum(x)
    refs = fill(zero(DataArrays.DEFAULT_POOLED_REF_TYPE), length(x))
    n = length(breaks)
    if absolute
        x2 = abs(x)
    else
        x2 = x
    end

    if leftequal
        for i in 1:length(x)
            if isna( x, i )
                refs[i] = 0
            elseif x2[i] <  breaks[1]
                refs[i] = 1
            elseif x2[i] >= breaks[end]
                refs[i] = n+1
            else
                refs[i] = searchsortedfirst(breaks, x2[i])
            end
        end
    else
        for i in 1:length(x)
            if isna( x, i )
                refs[i] = 0
            elseif x2[i] <= breaks[1]
                refs[i] = 1
            elseif x2[i] >  breaks[end]
                refs[i] = n+1
            else
                refs[i] = searchsortedlast(breaks, x2[i])
            end
        end
    end
    breakstrs = UTF8String[]
    formatter = _ -> prefix * format( _*scale,
            precision=precision,
            commas=commas,
            stripzeros=stripzeros,
            parens=parens,
            mixedfraction=mixedfraction,
            autoscale=autoscale,
            conversion=conversion ) * suffix
    for b in breaks
        push!( breakstrs, formatter( b ) )
    end
    pool = Array(UTF8String, n + 1)
    if rank
        rankwidth = length(string(n+1))
    end
    if !rank
        rankprefixfunc = _->""
    elseif reverse
        rankprefixfunc = j -> format( n+2-j, width=rankwidth ) * ranksep
    else
        rankprefixfunc = j -> format( j, width=rankwidth ) * ranksep
    end
    if compact
        if S <: Integer && scale == 1
            # we use 1...5, 6, 7...10, 11+etc.
            if leftequal
                breakminus1strs = UTF8String[]
                for b in breaks
                    push!( breakminus1strs, formatter( b-1 ) )
                end
                pool[1] = rankprefixfunc(1) * breakminus1strs[1] * "-"
                for i in 2:n
                    if breaks[i-1] == breaks[i]-1
                        pool[i] = rankprefixfunc(i)*breakstrs[i-1]
                    else
                        pool[i] = rankprefixfunc(i)*breakstrs[i-1]*"…"*breakminus1strs[i]
                    end
                end
                pool[n+1] = rankprefixfunc(n+1)*breakstrs[n]*"+"
            else
                breakplus1strs = UTF8String[]
                for b in breaks
                    push!( breakminus1strs, formatter( b+1 ) )
                end
                pool[1] = rankprefixfunc(1) * breakstrs[1] * "-"
                for i in 2:n
                    if breaks[i-1]+1 == breaks[i]
                        pool[i] = rankprefixfunc(i)*breakstrs[i]
                    else
                        pool[i] = rankprefixfunc(i)*breakplus1strs[i-1]*"…"*breakstrs[i]
                    end
                end
                pool[n+1] = rankprefixfunc(n+1)*breakplus1strs[n]*"+"
            end
        else # by the way, we don't show absolute in compact
            if leftequal
                brackL = "["
                brackR = ")"
            else
                brackL = "("
                brackR = "]"
            end
            pool[1] = rankprefixfunc(1) * breakstrs[1] * brackR
            for i in 2:n
                pool[i] = rankprefixfunc(i) * brackL * breakstrs[i-1]* "," *breakstrs[i] * brackR
            end
            pool[n+1] = rankprefixfunc(n+1) * brackL * breakstrs[n]
        end
    else
        if absolute
            label2 = "|"*label*"|"
        else
            label2 = label
        end
        if leftequal
            compareL = "≤"
            compareR = "<"
        else
            compareL = "<"
            compareR = "≤"
        end
        pool[1] = rankprefixfunc( 1 ) * label2 * compareR * breakstrs[1]
        for i in 2:n
            pool[i] = rankprefixfunc(i) * breakstrs[i-1] * compareL * label2 * compareR * breakstrs[i]
        end
        pool[n+1] = rankprefixfunc(n+1) * breakstrs[n] * compareL * label2
    end
    DataArrays.PooledDataArray(DataArrays.RefArray(refs), pool)
end
