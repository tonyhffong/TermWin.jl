# buildertest.jl
# Demonstrates how an external package would use TermWin's composable builder API
# to display a custom type without knowing TermWin internals.
#
# A package developer only needs to:
#   1. Define  TermWin.tshow_(x::TheirType; kwargs...)
#   2. Build the layout with @twlayout, vstack, or hstack
#   3. Use the existing newTwXxx constructors with that layout as first arg
#
# End users just call:  tshow(their_object)

using TermWin
using DataFrames

# ---------------------------------------------------------------------------
# Hypothetical package type — pretend this comes from an external package
# ---------------------------------------------------------------------------

struct ModelResult
    name::String
    summary::String
    coefficients::DataFrame
    diagnostics::DataFrame
end

# ---------------------------------------------------------------------------
# Option A: @twlayout macro — concise flat layout
# ---------------------------------------------------------------------------
# Comment out Option B and uncomment Option A to test the macro approach.

function TermWin.tshow_(r::ModelResult; kwargs...)
    @twlayout :vertical (title=r.name) begin
        viewer(r.summary;         height=5, width=80, showLineInfo=false, title="Summary")
        dftable(r.coefficients;   height=0.45,width=.9, title="Coefficients")
        dftable(r.diagnostics;    height=0.35,width=.9, title="Diagnostics")
    end
end

# ---------------------------------------------------------------------------
# Option B: vstack/hstack — composable, nesting-friendly
# ---------------------------------------------------------------------------
# Uncomment to use the function-based approach instead of the macro.
#
# function TermWin.tshow_(r::ModelResult; kwargs...)
#     vstack(; title=r.name) do outer
#         newTwViewer(outer, r.summary; height=5, showLineInfo=false, title="Summary")
#         hstack(outer) do inner
#             newTwDfTable(inner, r.coefficients; width=0.6, title="Coefficients")
#             newTwDfTable(inner, r.diagnostics;  width=0.4, title="Diagnostics")
#         end
#     end
# end

# ---------------------------------------------------------------------------
# Sample data
# ---------------------------------------------------------------------------

result = ModelResult(
    "OLS Regression",
    "R² = 0.87   F-stat = 42.3   p < 0.001\nN = 250 observations, 3 predictors",
    DataFrame(
        term     = ["(Intercept)", "x1", "x2"],
        estimate = [1.52,  0.31, -0.83],
        se       = [0.20,  0.05,  0.10],
        t        = [7.60,  6.20, -8.30],
        p        = [0.000, 0.000, 0.000],
    ),
    DataFrame(
        stat  = ["AIC",    "BIC",    "LogLik", "RMSE"],
        value = [312.4,   328.1,   -152.2,    0.41 ],
    ),
)

# ---------------------------------------------------------------------------
# Run it — just like an end-user would
# ---------------------------------------------------------------------------
tshow(result)
