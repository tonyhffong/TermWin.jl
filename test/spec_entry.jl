# spec_entry.jl — TTY demo of the spec-string entry widget (newTwSpecEntry).
#
# Usage:
#   julia --project=. test/spec_entry.jl
#
# newTwSpecEntry(scr, kind; columns=…) is a `newTwEntry(String)` wired to the
# UNTRUSTED DataFrameAggrSpec grammar. As you type it runs the real parser
# (`parseaggr` for :aggr, `parsedim` for :dim) on every keystroke and echoes the
# result on the dimmed hint line below the field:
#
#   * a ✓ summary when the spec parses (naming the reducer, or a dim's inferred
#     window/pivot kind),
#   * the parser's own rich rejection otherwise — including "did you mean 'mean'?"
#     repairs and, because we pass `columns`, did-you-mean on a misspelled column.
#
# Press `?` in any field to open the standard-template dropdown; pick one and edit
# it. The field stays free-text (templates are presets, not an enum).
#
# LaTeX-style unicode completion is on: type a Julia `\name` and press Tab to turn
# it into the char — `\circ`→∘ (the modifier combinator), `\ne`→≠, `\le`→≤,
# `\ge`→≥ (registered operators). Tab only completes when a `\name` sits before
# the cursor; otherwise it still moves focus.
#
# Things to try:
#   Aggr field    sum(_ * wt) / sum(wt)      then break it: maen(_)
#   Dim  field    cumsum(sales) |> orderby(date)   then a typo: cumsum(salse)
#   Dim  field    cumsum(sales) \circ<Tab> orderby(date)   → cumsum(sales) ∘ orderby(date)
#   Aggr field    mean(score) \ge<Tab> 50                  → mean(score) ≥ 50
#   Any field     press ?  to browse templates
#
# More quality-of-life:
#   * Tab also completes a partial COLUMN or FUNCTION name (after the `\name`
#     check): type `sum(sal` + Tab → `sum(sales`; ambiguous prefixes open a picker.
#   * Commit is GATED — Enter/blur is refused unless the spec parses, so a broken
#     spec can't be submitted (it beeps and stays; the ✗ hint tells you why).
#   * F6 pops the FULL parse diagnostic (untruncated) or a structural summary,
#     plus the available columns and the operator whitelist, in a scroll viewer.
#
# Controls:
#   \name + Tab     : complete to the unicode char (∘, ≠, ≤, ≥, …)
#   <prefix> + Tab  : complete a column / function name (picker if ambiguous)
#   Tab / Shift-Tab : move focus between fields (when nothing to complete)
#   ? (in a field)  : open the template dropdown
#   F6              : show full details / errors / operator whitelist
#   Enter           : validate current field and advance (refused if invalid)
#   F10             : submit → returns Dict{Symbol,Any} of the spec strings
#   Esc             : cancel  → nothing

using TermWin
using DataFrames

# The frame the specs are written against — its columns drive live validation.
df = DataFrame(
    region = ["East", "East", "West", "West", "West"],
    date   = ["2026-01", "2026-02", "2026-01", "2026-02", "2026-03"],
    sales  = [100, 140, 90, 120, 160],
    wt     = [1.0, 1.0, 2.0, 2.0, 1.0],
    score  = [55, 72, 40, 88, 91],
)
cols = propertynames(df)

println("Columns available to the specs: ", join(string.(cols), ", "))
println("Aggr templates (type-sensitive):")
foreach(t -> println("   ", t), spec_templates(:aggr; coltypes=df))
println()

# Passing `coltypes=df` makes the `?` dropdown type-sensitive (numeric columns →
# sum/median/…, text columns → uniqvalue/strjoinuniq/…) and also supplies the
# column list for live validation — no separate `columns=` needed.
result = withsession() do
    @twlayout (form=true, width=0.8,
               title="spec entry demo  —  type a spec, watch the parser echo below  (?: type-aware templates)") begin
        label("Aggregation specs reduce a column (`_` is the target); dim specs add a column from partition-mates.";
              style=:divider)
        specentry(:aggr; key=:measure, coltypes=df, titlewidth=14,
                  title="Aggr spec: ")
        specentry(:dim;  key=:bucket,  coltypes=df, titlewidth=14,
                  title="Dim spec: ")
        specentry(:dim;  key=:running, coltypes=df, titlewidth=14,
                  title="Running: ")
    end
    activateTwObj(rootTwScreen)
end

if result === nothing
    println("Cancelled.")
else
    println("Submitted spec strings:")
    for (k, v) in result
        println("  $k = $(repr(v))")
    end
    # Show they round-trip through the untrusted parser (safe to accept as-is).
    println("\nParsed (untrusted safe grammar, no eval):")
    for (k, v) in result
        isempty(strip(v)) && continue
        try
            spec = k === :measure ? parseaggr(v; columns=cols) : parsedim(v; columns=cols)
            println("  $k → ", spec)
        catch err
            println("  $k → REJECTED: ", sprint(showerror, err))
        end
    end
end
