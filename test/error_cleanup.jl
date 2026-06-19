# error_cleanup.jl — manual verification that withsession restores the terminal
# and surfaces the error, even when the session body throws.
#
# Usage (needs a real TTY):
#   julia --project=. test/error_cleanup.jl
#
# Expected:
#   * A brief flash of the alternate screen, then back to normal.
#   * The "boom" error + backtrace prints to a READABLE terminal.
#   * The "still alive" lines below print normally and the shell prompt afterward
#     echoes typed keys (no stuck mouse-tracking, cursor visible) — i.e. NOT locked.
#   * callcount returned to 0 and the notcurses context was released.

using TermWin

caught = nothing
try
    withsession() do
        # Pretend something blew up mid-session (could be widget construction or
        # an inject handler). The terminal is mid-takeover at this point.
        error("boom — simulated failure inside a TermWin session")
    end
catch err
    global caught = err
end

# If withsession's finally did its job, these print on a clean terminal:
println()
println("still alive: returned to the REPL/script cleanly")
println("caught error: ", caught === nothing ? "(none — unexpected!)" : sprint(showerror, caught))
println("TermWin.callcount  = ", TermWin.callcount, "   (expect 0)")
println("nc_context cleared = ", TermWin.nc_context === nothing, "   (expect true)")

@assert caught !== nothing            "withsession should have rethrown the error"
@assert TermWin.callcount == 0        "callcount must unwind to 0"
@assert TermWin.nc_context === nothing "notcurses context must be released"

println("\nerror_cleanup.jl: cleanup + surfacing OK")
