# Manual test for the threaded progress widget.
#
# Run:
#   julia -t auto --project=. test/progress_basic.jl
#
# The script runs three scenarios in order. After each one the dialog
# dismisses and the result is printed to the console.
#
#   1. NORMAL COMPLETION  - let the bar fill on its own (~4s).
#                           Expected: prints "sum = 20100".
#
#   2. COOPERATIVE CANCEL - press Esc (or Ctrl-K) while the bar is filling.
#                           Expected: prints a partial sum and "(cancelled)".
#
#   3. WORKER EXCEPTION   - the worker throws after ~0.5s.
#                           Expected: dialog dismisses, prints "(errored, returned nothing)".

using TermWin

println("\n=== Test 1: normal completion ===")
println("Let the bar fill. Expected sum = 20100.\n")

result1 = trun(title="Counting") do report, cancelled
    s = 0
    for i in 1:200
        cancelled() && return s
        sleep(0.02)
        s += i
        report(progress = i/200, text = "i = $i, sum = $s")
    end
    s
end
println("Result 1: sum = $result1")

println("\n=== Test 2: cooperative cancel ===")
println("Press Esc (or Ctrl-K) while the bar is filling.\n")

was_cancelled = Ref(false)
result2 = trun(title="Counting (cancel me)") do report, cancelled
    s = 0
    for i in 1:500
        if cancelled()
            was_cancelled[] = true
            return s
        end
        sleep(0.02)
        s += i
        report(progress = i/500, text = "i = $i, sum = $s")
    end
    s
end
if was_cancelled[]
    println("Result 2: partial sum = $result2 (cancelled)")
else
    println("Result 2: sum = $result2 (ran to completion - did you press Esc?)")
end

println("\n=== Test 3: worker exception ===")
println("Worker will throw after ~0.5s.\n")

result3 = trun(title="About to fail") do report, cancelled
    report(progress = 0.1, text = "starting")
    sleep(0.25)
    report(progress = 0.3, text = "about to fail")
    sleep(0.25)
    error("intentional failure")
end
if result3 === nothing
    println("Result 3: nothing (errored, returned nothing) — OK")
else
    println("Result 3: $result3 — UNEXPECTED, worker should have thrown")
end

println("\nAll tests done.")
