# entry_hintfn.jl — TTY demo of the `hintfn` entry option.
#
# Usage:
#   julia --project=. test/entry_hintfn.jl
#
# `hintfn` is a `buffer -> String` closure attached to a `newTwEntry`. It is
# recomputed on every keystroke and rendered as a dimmed line under the field —
# a live echo of what the current text *means*. It costs one extra row.
#
# This form wires four different kinds of live hint so you can watch each one
# update as you type:
#   Amount      — thousands-formatted + spelled-out numeric echo
#   Expression  — evaluate a Julia arithmetic expression as you type
#   Tenor       — resolve a relative-date tenor (e.g. T+2, T-1w) to a real Date
#   Slug        — normalize free text into a url-safe slug
#
# A `hintfn` that *throws* must never take the widget down — the field shows the
# error text instead. The Expression field demonstrates that: an incomplete or
# invalid expression just displays the parse/eval error on the hint line.
#
# Controls:
#   Tab / Shift-Tab : move focus between fields
#   Enter           : validate current field and advance
#   F10             : submit → returns Dict{Symbol,Any}
#   Esc             : cancel  → nothing

using TermWin
using Dates

# --- hint closures ---------------------------------------------------------

# 1. Thousands-separated + a coarse magnitude word for a numeric-looking string.
function amount_hint(buf::AbstractString)
    isempty(strip(buf)) && return "→ (enter a number)"
    n = tryparse(Float64, strip(buf))
    n === nothing && return "→ not a number"
    mag = abs(n) >= 1e9 ? "billions"  :
          abs(n) >= 1e6 ? "millions"  :
          abs(n) >= 1e3 ? "thousands" : "small"
    grouped = replace(string(round(Int, n)), r"(?<=\d)(?=(\d{3})+$)" => ",")
    "→ $grouped  ($mag)"
end

# 2. Evaluate a Julia arithmetic expression. A throwing hintfn is safe — the
#    widget catches it and shows the error text on the hint line.
function expr_hint(buf::AbstractString)
    isempty(strip(buf)) && return "→ (try: 2 + 3 * 4)"
    ex = Meta.parse(strip(buf))          # may throw on incomplete input
    "= " * string(eval(ex))              # may throw on undefined names, etc.
end

# 3. Resolve a relative-date tenor to a concrete Date, anchored on today.
#    Grammar: T, then optional +N / -N with a unit d(ay)/w(eek)/m(onth)/y(ear).
function tenor_hint(buf::AbstractString)
    s = strip(buf)
    isempty(s) && return "→ (e.g. T, T+2, T-1w, T+3m)"
    m = match(r"^T(?:([+-]\d+)([dwmy])?)?$"i, s)
    m === nothing && return "→ unrecognised tenor"
    d = today()
    if m.captures[1] !== nothing
        n = parse(Int, m.captures[1])
        unit = m.captures[2] === nothing ? "d" : lowercase(m.captures[2])
        d += unit == "w" ? Week(n)  :
             unit == "m" ? Month(n) :
             unit == "y" ? Year(n)  : Day(n)
    end
    "→ " * Dates.format(d, "yyyy-mm-dd, E")
end

# 4. Normalize free text into a lower-case url slug.
function slug_hint(buf::AbstractString)
    s = strip(lowercase(buf))
    isempty(s) && return "→ (slug preview)"
    slug = replace(s, r"[^a-z0-9]+" => "-")
    slug = strip(slug, '-')
    "→ /" * (isempty(slug) ? "" : slug)
end

# --- form ------------------------------------------------------------------

result = withsession() do
    @twlayout (form=true, title="hintfn demo  —  type in a field, watch the dimmed hint below it",
               width=0.7) begin
        entry(String; key=:amount, title="Amount",     width=52, titlewidth=12,
              hintfn = amount_hint)
        entry(String; key=:expr,   title="Expression", width=52, titlewidth=12,
              hintfn = expr_hint)
        entry(String; key=:tenor,  title="Tenor",       width=52, titlewidth=12,
              hintfn = tenor_hint)
        entry(String; key=:slug,   title="Title",       width=52, titlewidth=12,
              hintfn = slug_hint)
    end
    activateTwObj(rootTwScreen)
end

if result === nothing
    println("Cancelled.")
else
    println("Submitted:")
    for (k, v) in result
        println("  $k = $(repr(v))")
    end
end
