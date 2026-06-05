# ===== Widget contracts: inject outcome + caller result =====
#
# These types make two previously-implicit contracts explicit and
# self-documenting (see design/termwin-widget-authoring-rearchitecture.md, Part A).
#
# 1. The value `inject(o, token)` returns to the host event loop.
# 2. The value `activate(o)` returns to the *caller* of a modal widget.

"""
    InjectResult

Outcome of `inject(o, token)`. Every widget returns one of these, and the
screen/host event loop dispatches on it:

- `Handled` — token consumed; redraw if needed, keep focus
- `Ignored` — not ours; host may route elsewhere / bubble up
- `Accept`  — finish the widget with `o.value` as the result
- `Cancel`  — finish the widget with no result
"""
@enum InjectResult Handled Ignored Accept Cancel

# ===== Caller-facing result =====

"""
    Result{T}

One shape for what a modal widget hands back to its caller, replacing the
ad-hoc `o.value` / `Union{Dict,Nothing}` / `nothing` grab-bag:

- `Ok(value)`     — completed with a value
- `Cancelled()`   — user cancelled
- `Failed(err)`   — an exception was captured

Use [`unwrap`](@ref) to collapse to the legacy `value`-or-`nothing` convention.
"""
abstract type Result{T} end

struct Ok{T} <: Result{T}
    value::T
end
# (Julia auto-generates the `Ok(value)` outer constructor that infers T.)

struct Cancelled <: Result{Nothing} end

struct Failed <: Result{Nothing}
    err::Exception
end

isok(r::Result) = r isa Ok

"""
    unwrap(r::Result)

Collapse a `Result` to the legacy convention: `Ok` → its value, `Cancelled` →
`nothing`, `Failed` → rethrows the captured exception.
"""
unwrap(r::Ok) = r.value
unwrap(::Cancelled) = nothing
unwrap(r::Failed) = throw(r.err)
