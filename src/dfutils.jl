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
* Function: (most likely lambda) e.g. `df -> quantile( df[!,:col], 0.5 )`. It is expected
   to generate either a value (typically a scalar consistent to the column type), or
   a 1-row, 1-col dataframe.
""" ->
=#

DataFrameAggrCache = Dict{Any,Function}()

defaultAggr( ::Type ) = :uniqvalue
defaultAggr( ::Type{T} ) where {T<:Real} = :sum
defaultAggr( ::Type{Array{T,1}} ) where {T} = :unionall

function liftAggrSpecToFunc( c::Symbol, dfa::String )
    if haskey( DataFrameAggrCache, (c, dfa ) )
        return DataFrameAggrCache[ (c, dfa ) ]
    end
    ret = liftAggrSpecToFunc( c, Meta.parse( dfa ) )
    DataFrameAggrCache[ (c, dfa) ] = ret
end

# replace_col_syms: walk an expression and replace :col (QuoteNode or Expr(:quote,:col))
# with a gensym variable; populate membernames with col->gensym mapping
function replace_col_syms( ex, membernames::Dict )
    if isa( ex, QuoteNode ) && isa( ex.value, Symbol )
        sym = ex.value
        if !haskey( membernames, sym )
            membernames[sym] = gensym( string(sym) )
        end
        return membernames[sym]
    elseif isa( ex, Expr ) && ex.head == :quote && length(ex.args) == 1 && isa( ex.args[1], Symbol )
        sym = ex.args[1]
        if !haskey( membernames, sym )
            membernames[sym] = gensym( string(sym) )
        end
        return membernames[sym]
    elseif isa( ex, Expr ) && ex.head == :(.)
        # Member access like `StatsBase.mean` parses as
        # Expr(:(.), :StatsBase, QuoteNode(:mean)). The QuoteNode here is a
        # field name, NOT a column reference, so leave the whole expression
        # alone. Same treatment for deeper chains like `A.B.C`.
        return ex
    elseif isa( ex, Expr )
        return Expr( ex.head, [ replace_col_syms(a, membernames) for a in ex.args ]... )
    else
        return ex
    end
end

function liftAggrSpecToFunc( c::Symbol, dfa::Union{ Function, Symbol, Expr } )
    if isa( dfa, Function )
        return dfa
    end
    if haskey( DataFrameAggrCache, (c, dfa) )
        return DataFrameAggrCache[ (c, dfa ) ]
    end
    # "mean" or "Module.aggrfunc"
    if isa( dfa, Symbol ) || isa( dfa, Expr ) && dfa.head == :(.) && all( x->isa(x,Symbol), dfa.args )
        funnameouter = gensym( "DFAggr" )
        code = :(
            function $funnameouter( _df_::AbstractDataFrame )
            end )
        push!( code.args[2].args, Expr( :call, dfa, Expr( :ref, :_df_, :!, QuoteNode(c) ) ) )
        ret = eval( code )
    else # expr
        if !Base.Meta.isexpr( dfa, :call )
            error( string( dfa ) * " does not look like an aggregator function")
        end
        # disallow mutating function
        fname = dfa.args[1]
        if Base.Meta.isexpr( dfa, :curly )
            error( "DataFrameAggr: curly not supported")
        elseif !isa( fname, Symbol ) && !Base.Meta.isexpr( fname, :(.) )
            error( "DataFrameAggr: only simple function name please")
        end
        if occursin( "!", string(fname) )
            error( string(fname) * " seems to have side effects" )
        end

        # replace _ with _df_[!,$c], and then leverage replace_col_syms

        # before we do that, note that
        # (A) in DataFramesMeta, macro converts :x to Expr( :quote, :x ) but
        #     :( :x ) or parse( ":x" ) it is actually QuoteNode( :x ),
        #     so we need to do a little conversion in order to leverage that package
        cdfa = deepcopy( dfa )
        convertExpression!( cdfa, c )

        membernames = Dict{Symbol,Symbol}()
        cdfa = replace_col_syms(cdfa, membernames)
        funargs = map(x -> Expr( :ref, :_df_, :!, QuoteNode(x) ), collect(keys(membernames)))
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
        # Eval in Main so that module-qualified names in the user-supplied
        # expression (e.g. `StatsBase.mean(:_, :wcol)`) resolve against the
        # user's loaded packages rather than against TermWin's own imports.
        ret = Core.eval( Main, code )
    end
    DataFrameAggrCache[ (c, dfa) ] = ret
end

# used by aggregation lifting and calcpivot lifting
function convertExpression!( ex::Expr, column_ctx::Symbol = Symbol("") )
    # Do not descend into member-access expressions like `StatsBase.mean`
    # (Expr(:(.), :StatsBase, QuoteNode(:mean))). Their QuoteNode argument
    # is a field name, not a column reference, and rewriting it would
    # confuse `replace_col_syms` into treating `:mean` as a column.
    if ex.head == :(.)
        return
    end
    for i in 1:length( ex.args )
        a = ex.args[i]
        if isa( a, QuoteNode )
            if a.value == :_ && column_ctx != Symbol("")
                ex.args[i] = Expr( :quote, column_ctx )
            else
                ex.args[i] = Expr( :quote, a.value )
            end
        elseif isa( a, Expr )
            convertExpression!( a )
        end
    end
end

function unionall( x::AbstractVector )
    t = eltype( eltype( x ) )
    s = Set{t}()
    for el in skipmissing(x)
        push!( s, el... )
    end
    collect( s )
end

function uniqvalue( x::AbstractVector; skipna::Bool=true, skipempty::Bool=false )
    work = skipna ? collect(skipmissing(x)) : collect(x)
    if skipempty && eltype(work) <: AbstractString
        filter!( !isempty, work )
    end
    lvls = unique(work)
    length(lvls) == 1 ? lvls[1] : missing
end

struct CalcPivot
    spec::Expr
    by::Array{Symbol,1}
    CalcPivot( x::String, by::Array{Symbol,1}=Symbol[] ) = CalcPivot( Meta.parse(x), by )
    CalcPivot( x::String, by::Symbol ) = CalcPivot( Meta.parse(x), Symbol[ by ] )
    function CalcPivot( x::Expr, by::Symbol )
        CalcPivot( x, Symbol[ by ] )
    end
    function CalcPivot( ex::Expr, by::Array{Symbol,1}=Symbol[] )
        if !Base.Meta.isexpr( ex, :call )
            error( string( ex ) * " does not look like an aggregator function")
        end
        # disallow mutating function
        fname = ex.args[1]
        if Base.Meta.isexpr( ex, :curly )
            error( "CalcPivot: curly not supported")
        elseif !isa( fname, Symbol ) && !Base.Meta.isexpr( fname, :(.) )
            error( "CalcPivot: only simple function name please")
        end
        if occursin( "!", string(fname) )
            error( string(fname) * " seems to have side effects" )
        end

        if fname == :topnames # ensure we have the name in "by"
            # expect the first argument is a QuoteNode, or Expr( :quote, symbol )
            if isa( ex.args[2], QuoteNode )
                name_col = ex.args[2].value
            elseif Base.Meta.isexpr( ex.args[2], :quote )
                name_col = ex.args[2].args[1]
            else
                throw( "topnames: 1st argument expects a symbol (name column)")
            end
            if !in( name_col, by )
                new( ex, Symbol[ by..., name_col ] )
            else
                new( ex, by )
            end
        else
            new( ex, by )
        end
    end
end

CalcPivotFuncCache = Dict{ Any, Function }()
CalcPivotAggrDepCache = Dict{ Any, Array{Symbol,1} }()

# lifting a CalcPivot is a more complicated beast compared to aggregation.
# It is basically the fancier "apply" component of the # split-apply-combine strategy,
# with the "apply" also doing its nested split-apply-combine steps if necessary.

function liftCalcPivotToFunc( ex::Expr, by::Array{Symbol,1} )
    if haskey( CalcPivotFuncCache, (ex, by ) )
        return CalcPivotFuncCache[ (ex, by ) ]
    end

    cex = deepcopy( ex )
    convertExpression!( cex )
    funnameouter = gensym("calcpvt")
    funname = gensym()

    membernames = Dict{Symbol,Symbol}()
    cex = replace_col_syms(cex, membernames)
    # keys are the columns. values are the unique gensyms

    if !isempty( by ) # micro split-apply-combine
        funargs = map(x -> Expr( :ref, :byf, :!, QuoteNode(x) ), collect(keys(membernames)))
        aggregates = setdiff( collect( keys( membernames ) ), by )
        CalcPivotAggrDepCache[ (ex, by ) ] = aggregates
        # basically we want to do
        # byf = combine(groupby(_df_, by), lambdadf -> DataFrame(b = aggrfuncs[:b](lambdadf), c = aggrfuncs[:c](lambdadf), ... )
        aggr_args = Any[]
        lambdasym = gensym( "lambdadf" )
        for a in aggregates
            # Use invokelatest: aggrfuncs[:a] is created by liftAggrSpecToFunc's
            # eval(), which runs at a newer world age than funnameouter itself.
            # The lambda is compiled at funnameouter's world age, so a direct call
            # would fail with "method too new".
            push!( aggr_args, Expr( :kw, a, Expr( :call, :(Base.invokelatest), Expr( :ref, :aggrfuncs, QuoteNode( a ) ), lambdasym ) ) )
        end

        bycolsexpr=Expr( :vcat, map( x->QuoteNode(x), by )... ) # [ :a, :b, :c ... ]
        aggrcode = Expr( :->, lambdasym, Expr( :call, :DataFrame, aggr_args... ) )
        code = :(
            function $funnameouter( _df_::AbstractDataFrame, c::Symbol; kwargs... ) # we need kwargs here for aggregate specs
                aggrfuncs = Dict{Symbol,Function}()
                for (aggrc,spec) in kwargs
                    # this would throw if spec is not compliant, as usual
                    aggrfuncs[aggrc] = TermWin.liftAggrSpecToFunc(aggrc, spec )
                end
                # if kwargs doesn't have the required columns, it'll throw in this line
                byf = combine(groupby( _df_, $bycolsexpr ), $aggrcode)
                function $funname($(collect(values(membernames))...))
                    $cex
                end
                vals = $funname($(funargs...))
                ret = DataFrames.select(byf, $bycolsexpr)
                ret[!, c] = vals
                ret # This has all the "by" columns and the result, named by c
                # combine is done by the caller
            end
        )
    else # much simpler, we are doing line-by-line apply.
        # Common use case: a simple bucketing, or a line by line ranking.
        # a "pure" reading on empty "by" array may mean we aggregate everything in the
        # dataframe into one row, and then attach this row's value (a constant) into every row.
        # However, I have not known any legitimate use case for this.
        CalcPivotAggrDepCache[ (ex, by )] = Symbol[]
        funargs = map(x -> Expr( :ref, :_df_, :!, QuoteNode(x) ), collect(keys(membernames)))
        code = :(
            function $funnameouter( _df_::AbstractDataFrame ) # we need kwargs here for aggregate specs
                function $funname($(collect(values(membernames))...))
                    $cex
                end
                $funname($(funargs...))
                # the creation of column is done by the caller
            end
        )
    end
    ret = eval( code )
    CalcPivotFuncCache[ (ex, by ) ] = ret
end

function cut_categories( ::Type{S}, breaks::Vector{T};
    boundedness = :unbounded,
    leftequal=true, # t1 <= x < t2 or t1 < x <= t2?
    absolute=false, # t1 <= |x| < t2?
    rank=true, # add a rank to the string output for easier sorting?
    ranksep = ". ", # "1. t1 <= x < t2"?
    label = "", # if not compact, what label do we use for x?
    compact=(label==""), # <t1, [t1,t2), t2+. Further shortened for integer intervals with length=1
    reverse=false, # reverse the rank from the largest first?
    # the following format the boundary numbers
    # see Formatting.jl
    prefix="", suffix="", scale=1, precision=-1,
    commas=false,stripzeros=(precision==-1),parens=false,
    mixedfraction=false,autoscale=:none,conversion=""
    ) where {S<:Real, T<:Real}
    n = length(breaks)
    breakstrs = String[]
    function formatter(x)
        prefix * format( x*scale,
            precision=precision,
            commas=commas,
            stripzeros=stripzeros,
            parens=parens,
            mixedfraction=mixedfraction,
            autoscale=autoscale,
            conversion=conversion ) * suffix
    end
    for b in breaks
        push!( breakstrs, formatter( b ) )
    end
    if boundedness == :unbounded
        ncategories = n + 1
    elseif boundedness == :bounded
        ncategories = n-1
    else
        ncategories = n
    end
    pool = Vector{String}(undef, ncategories )
    if rank
        rankwidth = length(string(ncategories))
    end
    if !rank
        rankprefixfunc = _->""
    elseif reverse
        rankprefixfunc = j -> format( n+2-j, width=rankwidth ) * ranksep
    else
        rankprefixfunc = j -> format( j, width=rankwidth ) * ranksep
    end
    if compact
        if S <: Integer && T <: Integer && scale == 1
            # we use 1...5, 6, 7...10, 11+etc.
            if leftequal
                breakminus1strs = String[]
                for b in breaks
                    push!( breakminus1strs, formatter( b-1 ) )
                end
                poolindexshift = -1
                if boundedness in [ :unbounded, :boundedabove ]
                    pool[1] = rankprefixfunc(1) * "≤" * breakminus1strs[1]
                    poolindexshift = 0
                end
                for i in 2:n
                    if breaks[i-1] == breaks[i]-1
                        pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift)*breakstrs[i-1]
                    else
                        pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift)*breakstrs[i-1]*"…"*breakminus1strs[i]
                    end
                end
                if boundedness in [ :unbounded, :boundedbelow ]
                    pool[n+1+poolindexshift] = rankprefixfunc(n+1+poolindexshift)*breakstrs[n]*"+"
                end
            else
                breakplus1strs = String[]
                for b in breaks
                    push!( breakminus1strs, formatter( b+1 ) )
                end
                poolindexshift = -1
                if boundedness in [ :unbounded, :boundedabove ]
                    pool[1] = rankprefixfunc(1) *"≤ "* breakstrs[1]
                    poolindexshift = 0
                end
                for i in 2:n
                    if breaks[i-1]+1 == breaks[i]
                        pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift)*breakstrs[i]
                    else
                        pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift)*breakplus1strs[i-1]*"…"*breakstrs[i]
                    end
                end
                if boundedness in [ :unbounded, :boundedbelow ]
                    pool[n+1+poolindexshift] = rankprefixfunc(n+1+poolindexshift)*breakplus1strs[n]*"+"
                end
            end
        else # by the way, we don't show absolute in compact
            if leftequal
                brackL = "["
                brackR = ")"
                compareL = "<"
                compareR = "≥"
            else
                brackL = "("
                brackR = "]"
                compareL = "≤"
                compareR = ">"
            end
            poolindexshift = -1
            if boundedness in [ :unbounded, :boundedabove ]
                pool[1] = rankprefixfunc(1) * compareL * breakstrs[1]
                poolindexshift = 0
            end
            for i in 2:n
                if i == 2 && boundedness in [ :boundedbelow, :bounded ]
                    pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * "[" * breakstrs[i-1]* "," *breakstrs[i] * brackR
                elseif i == n && boundedness in [ :boundedabove, :bounded ]
                    pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * brackL * breakstrs[i-1]* "," *breakstrs[i] * "]"
                else
                    pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * brackL * breakstrs[i-1]* "," *breakstrs[i] * brackR
                end
            end
            if boundedness in [ :unbounded, :boundedbelow ]
                pool[n+1+poolindexshift] = rankprefixfunc(n+1+poolindexshift) * compareR * breakstrs[n]
            end
        end
    else
        if absolute
            label2 = "|"*label*"|"
        else
            label2 = label
        end
        if leftequal
            compareL = " ≤ "
            compareR = " < "
        else
            compareL = " < "
            compareR = " ≤ "
        end
        poolindexshift = -1
        if boundedness in [ :unbounded, :boundedabove ]
            pool[1] = rankprefixfunc( 1 ) * label2 * compareR * breakstrs[1]
            poolindexshift = 0
        end
        for i in 2:n
            if i == 2 && boundedness in [ :boundedbelow, :bounded ]
                pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * breakstrs[i-1] * " ≤ " * label2 * compareR * breakstrs[i]
            elseif i == n && boundedness in [ :boundedabove, :bounded ]
                pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * breakstrs[i-1] * compareL * label2 * " ≤ " * breakstrs[i]
            else
                pool[i+poolindexshift] = rankprefixfunc(i+poolindexshift) * breakstrs[i-1] * compareL * label2 * compareR * breakstrs[i]
            end
        end
        if boundedness in [ :unbounded, :boundedbelow ]
            pool[n+1+poolindexshift] = rankprefixfunc(n+1+poolindexshift) * breakstrs[n] * compareL * label2
        end
    end
    return pool
end

# boundedness:
#    unbounded    gives n+1 categories for n breaks.
#    boundedbelow gives n   categories for n breaks. Values below min will be missing
#    boundedabove gives n   categories for n breaks. Values above max will be missing
#    bounded      gives n-1 categories for n breaks. Values below min or above max will be missing
function discretize( x::AbstractArray{<:Union{S,Missing},1}, breaks::Vector{T};
    boundedness = :unbounded,
    bucketstrs = String[], # if provided, all of below will be ignored. length must be length(breaks)+1
    leftequal=true, # t1 <= x < t2 or t1 < x <= t2?
    absolute=false, # t1 <= |x| < t2?
    rank=true, # add a rank to the string output for easier sorting?
    ranksep = ". ", # "1. t1 <= x < t2"?
    label = "", # if not compact, what label do we use for x?
    compact=(label==""), # <t1, [t1,t2), t2+. Further shortened for integer intervals with length=1
    reverse=false, # reverse the rank from the largest first?
    # the following format the boundary numbers
    # see Formatting.jl
    prefix="", suffix="", scale=1, precision=-1,
    commas=false,stripzeros=(precision==-1),parens=false,
    mixedfraction=false,autoscale=:none,conversion=""
    ) where {S<:Real, T<:Real}
    if !issorted(breaks)
        sort!(breaks)
    end
    refs = fill(UInt32(0), length(x))
    n = length(breaks)
    if absolute
        x2 = abs.(x)
    else
        x2 = x
    end

    if boundedness == :unbounded
        below_min_mult = 1
        above_max_mult = 1
        ref_shift = 1
        ncategories = length( breaks ) + 1
    elseif boundedness == :boundedbelow
        below_min_mult = 0
        above_max_mult = 1
        ref_shift = 0
        ncategories = length( breaks )
    elseif boundedness == :boundedabove
        below_min_mult = 1
        above_max_mult = 0
        ref_shift = 1
        ncategories = length( breaks )
    elseif boundedness == :bounded
        below_min_mult = 0
        above_max_mult = 0
        ref_shift = 0
        ncategories = length( breaks ) - 1
    end

    if ncategories < 1
        error( "Too few categories. Change boundedness or add breaks")
    end

    if leftequal
        for i in 1:length(x)
            if ismissing( x[i] )
                refs[i] = 0
            elseif x2[i] <  breaks[1]
                refs[i] = below_min_mult
            elseif x2[i] > breaks[end]
                refs[i] = (n+ref_shift) * above_max_mult
            elseif x2[i] == breaks[end]
                if boundedness in [ :bounded, :boundedabove ]
                    refs[i] = ncategories
                else
                    refs[i] = n+ref_shift
                end
            else
                refs[i] = searchsortedlast(breaks, x2[i]) + ref_shift
            end
        end
    else
        for i in 1:length(x)
            if ismissing( x[i] )
                refs[i] = 0
            elseif x2[i] < breaks[1]
                refs[i] = below_min_mult
            elseif x2[i] > breaks[end]
                refs[i] = (n+ref_shift) * above_max_mult
            else
                refs[i] = searchsortedfirst(breaks, x2[i])
            end
        end
    end

    if length( bucketstrs ) != 0
        if length( bucketstrs ) != ncategories
            error( "bucketstrs expected to have size " * string( ncategories ) *
                 ". Got " * string( length( bucketstrs ) ) )
        end
        if maximum( refs ) > ncategories
            maxref = maximum( refs )
            s = "ncategories < max refs \n maxref="  * string( maxref ) * "\n ncategories=" * string( ncategories )
            s *= "\n buckets = " * string( bucketstrs )
            idx = findfirst( isequal(maxref), refs )
            s *= "\n Example x = " * string(x2[idx] )
            s *= "\n breaks" * string( breaks )
            error( s )
        end
        return CategoricalArray( Union{Missing,String}[ refs[i] == 0 ? missing : String(bucketstrs[refs[i]]) for i in 1:length(refs) ] )
    end
    pool = cut_categories( S, breaks,
        boundedness = boundedness,
        leftequal   = leftequal,
        absolute    = absolute,
        rank        = rank,
        ranksep     = ranksep,
        label       = label,
        compact     = compact,
        reverse     = reverse,
        prefix=prefix, suffix=suffix, scale=scale, precision=precision,
        commas=commas,stripzeros=stripzeros,parens=parens,
        mixedfraction=mixedfraction,autoscale=autoscale,conversion=conversion
        )

    CategoricalArray( Union{Missing,String}[ refs[i] == 0 ? missing : pool[refs[i]] for i in 1:length(refs) ] )
end

# quantile-based auto-breaks
# weighted quantile is not implemented
# use scale=100.0, suffix="%", to express the quantiles in percentages
function discretize( x::AbstractArray{S,1}; quantiles = Float64[], ngroups::Int = 4, kwargs... ) where {S<:Real}
    if length( quantiles ) != 0
        if any( x -> x < 0.0 || x > 1.0 , quantiles )
            error( "illegal quantile numbers outside [0,1]")
        end
        if !issorted(quantiles)
            sort!(quantiles)
        end
        if quantiles[1] != 0.0
            insert!( quantiles, 1, 0.0 )
        end

        if quantiles[end] != 1.0
            push!( quantiles, 1.0 )
        end
        bucketstrs = cut_categories( Float64, quantiles; boundedness = :bounded, kwargs... )
        discretize( x, quantile( x, quantiles ); bucketstrs = bucketstrs, boundedness = :bounded, kwargs... )
    else
        qs = collect(0:ngroups) ./ ngroups
        bucketstrs = cut_categories( Float64, qs; boundedness = :bounded, kwargs... )
        discretize( x, quantile( x, qs); bucketstrs = bucketstrs, boundedness = :bounded, kwargs... )
    end
end

# names are expected to be unique
# n is the maximum rank number to report. Actual outcome may depend on existence of a tie, and dense option
function topnames( name::AbstractArray{S,1}, measure::AbstractArray{T,1}, n::Int;
    absolute=false,
    ranksep = ". ",
    dense = true, # if there is a tie in the 2nd place, do we do "1,2,2,4", or "1,2,2,3"
    tol = 0,  # if absolute, what is the smallest contribution that we would consider
    others = "Others",
    parens = false # put parentheses around names with negative measure?
    ) where {S<:AbstractString, T<:Real}

    if absolute
        df = DataFrame( name = name, measure = measure, absmeasure = abs.(measure) )
        if tol > 0 # filter out too small names
            dfsorted = sort( df[ df.absmeasure .>= tol, :], [:absmeasure, :measure], rev=[true,true] )
        else
            dfsorted = sort( df, [:absmeasure, :measure], rev = [true, true] )
        end
    else
        df = DataFrame( name = name, measure = measure )
        dfsorted = sort( df, [:measure], rev = [true] )
    end

    rankcount = 1
    rankwidth = length( string( n ) )
    nr = nrow( dfsorted )

    if !absolute
        pool = String[]
        refs = fill(UInt32(0), nr)
        lastval  = zero( T )
        lastrank = 0
        for r in 1:nr
            if ismissing( dfsorted[r, :measure] )
                continue
            else
                val = dfsorted[ r, :measure ]
                if lastrank != 0 && lastval == val # tie
                    push!( pool, format( lastrank, width=rankwidth ) * ranksep * dfsorted[ r, :name ] )
                    refs[r] = length( pool )
                    if !dense
                        rankcount += 1
                    end
                elseif rankcount > n
                    break
                else
                    push!( pool, format( rankcount, width=rankwidth ) * ranksep * dfsorted[ r, :name ] )
                    lastrank = rankcount
                    lastval = val
                    refs[r] = length( pool )
                    rankcount += 1
                end
            end
        end
        dfsorted[!, :rankstr] = Union{Missing,String}[ refs[r] == 0 ? missing : pool[refs[r]] for r in 1:nr ]
        rankdict = Dict{String, Union{String,Missing}}(
            dfsorted[r, :name] => dfsorted[r, :rankstr] for r in 1:nr
        )
        jdf_rankstr = Union{String,Missing}[ get(rankdict, n, missing) for n in name ]
    else
        rankedflag = fill( false, nr )
        lastval  = zero( T )
        lastrank = 0
        for r in 1:nr
            if ismissing( dfsorted[r, :measure] )
                continue
            else
                val = dfsorted[ r, :measure ]
                if lastrank != 0 && lastval == val # tie
                    rankedflag[r] = true
                    if !dense
                        rankcount += 1
                    end
                elseif rankcount > n
                    break
                else
                    rankedflag[r] = true
                    lastrank = rankcount
                    lastval = val
                    rankcount += 1
                end
            end
        end
        dfsorted[!, :rankedflag] = rankedflag
        dfsorted2 = sort( dfsorted, [:measure], rev = [true] )
        rankstr = Union{Missing,String}[ missing for _ in 1:nr ]
        rankcount = 1
        lastval  = zero( T )
        lastrank = 0
        for r in 1:nr
            if ismissing( dfsorted2[r, :measure] )
                continue
            elseif dfsorted2[ r, :rankedflag ]
                val = dfsorted2[ r, :measure ]
                if lastrank != 0 && lastval == val # tie
                    if parens && val < 0
                        rankstr[r] = format( lastrank, width=rankwidth ) * ranksep * "("*dfsorted2[r,:name]*")"
                    else
                        rankstr[r] = format( lastrank, width=rankwidth ) * ranksep * dfsorted2[r,:name]
                    end
                    if !dense
                        rankcount += 1
                    end
                elseif rankcount > n
                    break
                else
                    if parens && val < 0
                        rankstr[r] = format( rankcount, width=rankwidth ) * ranksep * "("*dfsorted2[r,:name]*")"
                    else
                        rankstr[r] = format( rankcount, width=rankwidth ) * ranksep * dfsorted2[r,:name]
                    end
                    lastrank = rankcount
                    lastval = val
                    rankcount += 1
                end
            end
        end
        dfsorted2[!, :rankstr] = rankstr
        rankdict = Dict{String, Union{String,Missing}}(
            dfsorted2[r, :name] => dfsorted2[r, :rankstr] for r in 1:nrow(dfsorted2)
        )
        jdf_rankstr = Union{String,Missing}[ get(rankdict, n, missing) for n in name ]
    end

    # replace missing with "others"
    CategoricalArray( [ ismissing(x) ? others : x for x in jdf_rankstr ] )
end

function describe( io::IO, dv::AbstractVector )
    show( io, DataFrames.describe( DataFrame( x=dv ) ) )
    println( io )
end
