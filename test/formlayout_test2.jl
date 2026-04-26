# labeltest.jl — demo for spacer and label layout helpers
#
# Usage:
#   julia --project=. test/labeltest.jl
#
# Shows all three label styles (plain, header, divider) and spacers used to
# group fields in a form.  Fill in the fields and press F10 to submit.
#
# Controls:
#   Tab / Shift-Tab  : move focus
#   Enter            : advance to next field
#   F10              : submit → prints collected dict
#   Esc              : cancel

using TermWin

TermWin.initsession()

form = @twlayout :vertical (form=true, title="Server Config", height=0.75, width=0.55) begin

    label("Connection";  style=:header)
    entry(String; key=:host, title="Host",     width=35, titlewidth=10)
    entry(Int;    key=:port, title="Port",     width=18, titlewidth=10)
    entry(String; key=:db,   title="Database", width=35, titlewidth=10)

    spacer()

    label("Credentials"; style=:divider)
    entry(String; key=:user, title="Username", width=25, titlewidth=10)
    entry(String; key=:pass, title="Password", width=25, titlewidth=10)

    spacer()

    label("Options"; style=:divider)
    popup(["none","require","verify-full"]; key=:ssl,   title="SSL mode")
    popup(["5","10","30","60"];             key=:timeout, title="Timeout (s)")

    spacer(height=2)

    label("F10 to connect  ·  Esc to cancel")

end

activateTwObj( rootTwScreen )
result = form.value
TermWin.endsession()

if result === nothing
    println("Cancelled.")
else
    println("Config:")
    for (k, v) in result
        println("  :$k => $(repr(v))")
    end
end
