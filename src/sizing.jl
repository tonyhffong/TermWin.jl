# ===== Flexible sizing hints for vstack / hstack / @twlayout =====
#
# A child's `height=`/`width=` may be a literal size OR a hint that the layout
# engine resolves against the container and the widget's own content:
#
#   Int          fixed rows/cols                         (unchanged)
#   Float (0,1]  fraction of the container canvas         (unchanged)
#   :content     size to the widget's natural content extent
#   :fill        grow to consume leftover main-axis space (weight 1)
#   Flex(w)      like :fill, but split leftover space by relative weight w
#
# "Main axis" is the stacking direction: height in a vstack, width in an hstack.
# On the *cross* axis a fill spec means "span the container" (same role the
# existing fractional-fill path plays for separators). Hints ride the existing
# `Any`-typed TwObj.desired{Height,Width} fields, so no struct change is needed.
#
# Distribution happens in `resolve_flex!` (twlist.jl), the main-axis analogue of
# update_list_canvas's cross-axis fill pass. See design/codebase-review.md and
# the plan in design/ for the rationale.

"Weighted fill hint: `Flex(2)` claims twice the leftover space of `Flex(1)`/`:fill`."
struct Flex
    weight::Float64
end
Flex() = Flex(1.0)

"A size argument: a literal `Real` (Int rows/cols or Float fraction) or a hint (`:content`/`:fill`/`Flex`)."
const SizeSpec = Union{Real,Symbol,Flex}

# ── spec predicates over a stored desired* value ──────────────────────────────

"True if `spec` is a main-axis fill hint (`:fill` or `Flex`)."
is_flex(spec) = spec === :fill || spec isa Flex

"True if `spec` requests natural-content sizing (`:content`/`:auto`)."
is_content(spec) = spec === :content || spec === :auto

"Relative grow weight of a fill spec (`:fill` → 1.0)."
flex_weight(spec) = spec isa Flex ? spec.weight : 1.0

# Cross-axis "span the container" factor, or `nothing` if `spec` is not a fill.
# A Float in (0,1] keeps its fraction; `:fill`/`Flex` span fully (1.0).
function cross_fill_factor(spec)
    if spec isa AbstractFloat && 0.0 < spec <= 1.0
        return Float64(spec)
    elseif spec === :fill || spec isa Flex
        return 1.0
    else
        return nothing
    end
end

# Resolve one dimension spec to a provisional integer size. `main` marks the
# stacking axis: a fill spec there gets a provisional 1 (finalized later by
# resolve_flex!); on the cross axis it spans the parent. `:content` resolves to
# the widget's natural extent (`nat`), clamped into [1, parmax].
function resolve_dim(spec, parmax::Int, nat::Int; main::Bool)
    if spec isa Integer
        return min(Int(spec), parmax)
    elseif spec isa AbstractFloat
        (0.0 < spec <= 1.0) || throw("Illegal size " * string(spec))
        v = round(Int, parmax * spec)
        v == 0 && throw("size is too small")
        return v
    elseif spec === :content || spec === :auto
        return clamp(nat, 1, parmax)
    elseif spec === :fill || spec isa Flex
        return main ? 1 : parmax
    else
        throw("Illegal size " * string(spec))
    end
end

# ── pure main-axis allocator ──────────────────────────────────────────────────
# The arithmetic core of resolve_flex!, kept window-free so it is unit-testable
# without a TTY. Given each child's main-axis spec plus its current and natural
# sizes, return the resolved main-axis size for every child:
#   - `:content` → its natural size (clamped to the budget when bounded);
#   - `:fill`/`Flex` → an even/weighted split of the leftover space when bounded,
#     else a fallback to natural size;
#   - everything else keeps `presizes[i]` (literal Int/Float, or a nested list).
# `budget <= 0` means the container is unbounded (a nested shrink-wrap list).
function allocate_main(specs, presizes::Vector{Int}, naturals::Vector{Int}, budget::Int)
    n = length(specs)
    out = copy(presizes)
    bounded = budget > 0
    for i in 1:n
        if is_content(specs[i])
            out[i] = bounded ? clamp(naturals[i], 1, budget) : max(1, naturals[i])
        end
    end
    flexidx = [i for i in 1:n if is_flex(specs[i])]
    if !isempty(flexidx)
        if bounded
            used = sum(out[i] for i in 1:n if !is_flex(specs[i]); init = 0)
            remaining = max(0, budget - used)
            total_w = sum(flex_weight(specs[i]) for i in flexidx)
            acc = 0
            for (k, i) in enumerate(flexidx)
                share = k < length(flexidx) ?
                    max(1, floor(Int, remaining * flex_weight(specs[i]) / total_w)) :
                    max(1, remaining - acc)   # last child absorbs the rounding remainder
                acc += share
                out[i] = share
            end
        else
            for i in flexidx
                out[i] = max(1, naturals[i])
            end
        end
    end
    return out
end

# ── natural content extent ────────────────────────────────────────────────────
# Queried by the layout engine for `:content` sizing. Default: the widget's
# current allocated size; variable widgets (trees, tables, viewer) override with
# their real content extent (rows / summed column widths). Defined here so the
# generic fallback exists before any widget file is loaded.

"Natural content height (rows) a widget would like, used for `:content` sizing."
natural_height(o::TwObj) = o.height

"Natural content width (cols) a widget would like, used for `:content` sizing."
natural_width(o::TwObj) = o.width
