type FormatHints
    width         :: Int  # column width, not the format width
    scale         :: Real
    precision     :: Int
    commas        :: Bool
    stripzeros    :: Bool
    parens        :: Bool
    rednegative   :: Bool # print in red when negative?
    hidezero      :: Bool
    alternative   :: Bool
    mixedfraction :: Bool
    suffix        :: UTF8String
    autoscale     :: Symbol
    conversion    :: ASCIIString
end

function FormatHints{T<:Integer}( ::Type{T} )
    FormatHints( 8, 1, 0, true, false, false, true, true, false, false, "", :none, "d" )
end
function FormatHints{T<:Unsigned}( ::Type{T} )
    FormatHints( 8, 1, 0, true, false, false, true, true, false, false, "", :none, "x" )
end
function FormatHints{T<:AbstractFloat}( ::Type{T} )
    FormatHints( 10, 1.0, 2, true, false, false, true, true, false, false, "", :none, "f" )
end
function FormatHints{T<:Rational}( ::Type{T} )
    FormatHints( 12, 1, 0, false, false, false, true, true, false, true, "", :none, "s" )
end
function FormatHints( ::Type{Date} )
    FormatHints( 10, 1, 0, false, false, false, false, false, false, false,"", :none,
       "yyyy-mm-dd" )
end
function FormatHints( ::Type{DateTime} )
    FormatHints( 20, 1, 0, false, false, false, false, false, false, false,"", :none,
       "yyyy-mm-dd HH:MM:SS" )
end
function FormatHints( ::Type{} )
    FormatHints( 14, 1, 0, false, false, false, true, true, false, false, "", :none, "s" )
end

function applyformat{T<:Number}( v::T, fmt::FormatHints )
    if fmt.hidezero && v == 0
        ""
    else
        format( v * fmt.scale,
            precision     = fmt.precision,
            commas        = fmt.commas,
            stripzeros    = fmt.stripzeros,
            parens        = fmt.parens,
            alternative   = fmt.alternative,
            mixedfraction = fmt.mixedfraction,
            suffix        = fmt.suffix,
            autoscale     = fmt.autoscale,
            conversion    = fmt.conversion
            )
    end
end

function applyformat( v::Union{Date,DateTime}, fmt::FormatHints )
    Dates.format( v, fmt.conversion )
end

function applyformat{T<:AbstractString}( v::T, fmt::FormatHints )
    @lintpragma( "Ignore unused fmt" )
    return v
end

function applyformat( v::AbstractArray, fmt::FormatHints )
    strs = UTF8String[]
    for s in v
        push!( strs, applyformat( s, fmt ) )
    end
    join( strs, "," )
end

function applyformat( v, fmt::FormatHints )
    @lintpragma( "Ignore unused fmt" )
    return string( v )
end
