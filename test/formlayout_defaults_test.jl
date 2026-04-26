# formlayout_defaults_test.jl — demo for the `defaults` dict round-trip
#
# Usage:
#   julia --project=. test/formlayout_defaults_test.jl
#
# The form opens twice.  On the second opening every field is pre-populated
# with whatever was submitted (or left at its widget default) in round 1.
# Press F10 to submit, Esc to cancel either round.
#
# Controls:
#   Tab / Shift-Tab  : move focus
#   Enter            : validate current field and advance
#   F10              : submit  → prints Dict{Symbol,Any}
#   Esc              : cancel  → prints "cancelled"
#   F1               : help

using TermWin, Dates

function run_form(defaults = nothing)
    TermWin.initsession()

    form = @twlayout :vertical (form=true, title="Edit User", height=0.75, width=0.55,
                                defaults=defaults) begin
        entry(String;  key=:name,       title="Name",       width=30, titlewidth=12)
        entry(Int;     key=:age,        title="Age",        width=20, titlewidth=12)
        entry(Float64; key=:score,      title="Score",      width=25, titlewidth=12)
        multiselect(["read","write","exec"];
                    key=:permissions, title="Permissions")
        entry(Date;    key=:start_date, title="Start date", width=25, titlewidth=12)
    end

    activateTwObj(rootTwScreen)
    result = form.value
    TermWin.endsession()
    result
end

# --- Round 1: no defaults, fill in from scratch ---
println("=== Round 1: fill in the form, then press F10 ===")
r1 = run_form()

if r1 === nothing
    println("Round 1 cancelled — exiting.")
else
    println("\nRound 1 result:")
    for (k, v) in sort(collect(r1); by=x->string(x[1]))
        println("  :$k => $(repr(v))")
    end

    # --- Round 2: pre-populate with round-1 result ---
    println("\n=== Round 2: same form pre-filled with round-1 values ===")
    r2 = run_form(r1)

    if r2 === nothing
        println("Round 2 cancelled.")
    else
        println("\nRound 2 result:")
        for (k, v) in sort(collect(r2); by=x->string(x[1]))
            println("  :$k => $(repr(v))")
        end
    end
end
