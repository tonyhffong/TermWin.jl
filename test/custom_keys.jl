# custom_keys.jl — TTY demo of custom layout key bindings (on_key + keys=).
#
# Usage:
#   julia --project=. test/custom_keys.jl
#
# Controls inside the form:
#   Tab / Shift-Tab : move focus between fields
#   Enter           : validate current field and advance to next
#   F5              : custom — preview the current values in a popup (form stays open)
#   Ctrl-S          : custom — "save draft" and exit, returning the snapshot
#   F10             : submit form → returns Dict{Symbol,Any}
#   Esc             : cancel form → nothing
#   F1              : help (lists the custom keys too)

using TermWin

# A custom key's callback receives the live data snapshot (Dict{Symbol,Any}) —
# the same dict F10-submit would return.
function preview(snap)
    lines = ["Current values:", ""]
    for (k, v) in snap
        push!(lines, "  $k = $(repr(v))")
    end
    viewer = newTwViewer(rootTwScreen, join(lines, "\n");
                         posy = :center, posx = :center,
                         showLineInfo = false, bottomText = "Esc to continue")
    TermWin.raiseTwObject(viewer)
    Handled            # stay in the form
end

# withsession guarantees the terminal is restored even if anything below throws.
result = withsession() do
    @twlayout (form=true, title="New Draft  (F5:preview  Ctrl-S:save)",
               height=0.6, width=0.5,
               keys=[
                   on_key(:F5,     "preview", preview),
                   on_key(:ctrl_s, "save",    snap -> Accept),  # exit, return snap
               ]) begin
        entry(String; key=:title,  title="Title",  width=40, titlewidth=8)
        entry(String; key=:author, title="Author", width=40, titlewidth=8)
        entry(Int;    key=:year,   title="Year",   width=20, titlewidth=8)
    end
    activateTwObj(rootTwScreen)
end

if result === nothing
    println("Cancelled.")
else
    println("Result snapshot:")
    for (k, v) in result
        println("  $k = $(repr(v))")
    end
end
