# TTY demo for reactive section visibility (`visible_when`).
#
# A form whose "Advanced" section appears only when the Mode popup is switched to
# "Advanced", and collapses (reclaiming its rows) otherwise. Tab between fields;
# change Mode and watch the layout reflow live. F10 submits, Esc cancels.
#
# Run:  julia --project=. test/visibility_demo.jl

using TermWin

result = withsession() do
    form = @twlayout (form = true, title = "New Job  (Tab / change Mode / F10 / Esc)") begin
        popup(["Basic", "Advanced"]; key = :mode, title = "Mode")
        entry(String; key = :name, title = "Job name", width = 30)
        # This whole section is shown only while Mode == "Advanced".
        vstack(begin
            label("── Advanced options ──"; style = :divider)
            entry(Int;    key = :threads, title = "Threads", width = 10)
            entry(String; key = :host,    title = "Host",    width = 30)
        end; visible_when = snap -> get(snap, :mode, "Basic") == "Advanced")
        entry(String; key = :notes, title = "Notes", width = 40)
    end
    activateTwObj(rootTwScreen)
    form.value
end

println("\nForm result: ", result)
