mutable struct FormatHints
    width::Int  # column width, not the format width
    scale::Real
    precision::Int
    commas::Bool
    stripzeros::Bool
    parens::Bool
    rednegative::Bool # print in red when negative?
    hidezero::Bool
    alternative::Bool
    mixedfraction::Bool
    suffix::String
    autoscale::Symbol
    conversion::String
end

function FormatHints(::Type{T}) where {T<:Integer}
    FormatHints(8, 1, 0, true, false, false, true, true, false, false, "", :none, "d")
end
function FormatHints(::Type{T}) where {T<:Unsigned}
    FormatHints(8, 1, 0, true, false, false, true, true, false, false, "", :none, "x")
end
function FormatHints(::Type{T}) where {T<:AbstractFloat}
    FormatHints(10, 1.0, 2, true, false, false, true, true, false, false, "", :none, "f")
end
function FormatHints(::Type{T}) where {T<:Rational}
    FormatHints(12, 1, 0, false, false, false, true, true, false, true, "", :none, "s")
end
function FormatHints(::Type{Date})
    FormatHints(
        10,
        1,
        0,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        "",
        :none,
        "yyyy-mm-dd",
    )
end
function FormatHints(::Type{DateTime})
    FormatHints(
        20,
        1,
        0,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        "",
        :none,
        "yyyy-mm-dd HH:MM:SS",
    )
end
function FormatHints(::Type{})
    FormatHints(14, 1, 0, false, false, false, true, true, false, false, "", :none, "s")
end

function applyformat(v::T, fmt::FormatHints) where {T<:Number}
    if fmt.hidezero && v == 0
        ""
    else
        format(
            v * fmt.scale,
            precision = fmt.precision,
            commas = fmt.commas,
            stripzeros = fmt.stripzeros,
            parens = fmt.parens,
            alternative = fmt.alternative,
            mixedfraction = fmt.mixedfraction,
            suffix = fmt.suffix,
            autoscale = fmt.autoscale,
            conversion = fmt.conversion,
        )
    end
end

function applyformat(v::Union{Date,DateTime}, fmt::FormatHints)
    Dates.format(v, fmt.conversion)
end

function applyformat(v::T, fmt::FormatHints) where {T<:AbstractString}
    return v
end

function applyformat(v::AbstractArray, fmt::FormatHints)
    strs = String[]
    for s in v
        push!(strs, applyformat(s, fmt))
    end
    join(strs, ",")
end

function applyformat(v, fmt::FormatHints)
    return string(v)
end
