# formtest.jl — test the composable data-entry form feature
#
# Usage:
#   julia --project=. test/formtest.jl
#
# Controls inside the form:
#   Tab / Shift-Tab  : move focus between fields
#   Enter            : validate current field and advance to next
#   F10              : submit form  → prints Dict{Symbol,Any}
#   Esc              : cancel form  → prints "cancelled"
#   F1               : help

using TermWin

# ---------------------------------------------------------------------------
# Option A: @twlayout macro (concise)
# ---------------------------------------------------------------------------

TermWin.initsession()

form = @twlayout :vertical (form=true, title="New User", height=0.6, width=0.5) begin
    entry(String; key=:username, title="Username",   width=28)
    entry(Int;    key=:age,      title="Age",         width=10)
    popup(["Engineering", "Sales", "Operations", "HR"];
          key=:department, title="Department")
    multiselect(["read", "write", "exec"];
                key=:permissions, title="Permissions")
end

activateTwObj( rootTwScreen )
result = form.value
TermWin.endsession()

# ---------------------------------------------------------------------------
# Option B: vstack / hstack (uncomment to use instead of Option A)
# ---------------------------------------------------------------------------
#
# TermWin.initsession()
#
# form = vstack(rootTwScreen; form=true, title="New User", height=0.6, width=0.5) do parent
#     newTwEntry(parent, String; key=:username,    title="Username",    width=28)
#     newTwEntry(parent, Int;    key=:age,         title="Age",         width=10)
#     newTwPopup(parent, ["Engineering","Sales","Operations","HR"];
#                key=:department, title="Department")
#     newTwMultiSelect(parent, ["read","write","exec"];
#                      key=:permissions, title="Permissions")
# end
#
# activateTwObj( rootTwScreen )
# result = form.value
# TermWin.endsession()

# ---------------------------------------------------------------------------
# Show result
# ---------------------------------------------------------------------------

if result === nothing
    println("Form cancelled.")
else
    println("Form submitted:")
    for (k, v) in result
        println("  :$k => $(repr(v))")
    end
end
