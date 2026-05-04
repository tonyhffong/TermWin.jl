# Automated unit test for the threaded progress widget plumbing.
# No TTY required — exercises Channel + Atomic + Task + tick() in isolation.
#
# Run:
#   julia --project=. test/progress_unit.jl

using Test
using TermWin

const TW = TermWin

# Build a TwProgressData + TwObj manually, bypassing newTwProgress() so the
# test does not require an Notcurses session. We push redrawTime far into the
# future so tick() never calls refresh() (which would touch o.window == nothing).
function make_progress(workTask::Task,
                      updates::Channel{TW.ProgressUpdate},
                      cancelFlag::Threads.Atomic{Bool})
    data = TW.TwProgressData(
        updates, cancelFlag, workTask,
        0.0, "", time(), time() + 1e9,   # redrawTime = far future → no refresh()
    )
    TW.TwObj(data, Val{:Progress})
end

@testset "ProgressUpdate struct" begin
    u1 = TW.ProgressUpdate(0.5, "halfway")
    @test u1.progress === 0.5
    @test u1.text === "halfway"

    u2 = TW.ProgressUpdate(nothing, "msg only")
    @test u2.progress === nothing
    @test u2.text === "msg only"

    u3 = TW.ProgressUpdate(0.25, nothing)
    @test u3.progress === 0.25
    @test u3.text === nothing
end

@testset "tick drains channel and updates state" begin
    ch    = Channel{TW.ProgressUpdate}(64)
    flag  = Threads.Atomic{Bool}(false)
    # A task that just sleeps long enough not to finish during the test
    task  = Threads.@spawn (sleep(60); 42)
    o     = make_progress(task, ch, flag)

    # Push three updates; tick should drain all and apply latest non-nothing fields
    put!(ch, TW.ProgressUpdate(0.1, "step 1"))
    put!(ch, TW.ProgressUpdate(0.5, nothing))      # progress only
    put!(ch, TW.ProgressUpdate(nothing, "step 3")) # text only

    status = TW.tick(o)
    @test status === :got_it
    @test o.data.progress ≈ 0.5
    @test o.data.text == "step 3"

    # Tick with no updates should be a no-op returning :got_it
    status2 = TW.tick(o)
    @test status2 === :got_it
    @test o.data.progress ≈ 0.5
    @test o.data.text == "step 3"

    # Cleanup: cancel the task so it doesn't linger
    schedule(task, InterruptException(); error=true)
end

@testset "tick returns :exit_ok on successful completion" begin
    ch   = Channel{TW.ProgressUpdate}(64)
    flag = Threads.Atomic{Bool}(false)

    task = Threads.@spawn begin
        put!(ch, TW.ProgressUpdate(0.5, "halfway"))
        put!(ch, TW.ProgressUpdate(1.0, "done"))
        "the answer"
    end
    wait(task)   # task is finished by the time we tick

    o = make_progress(task, ch, flag)
    status = TW.tick(o)
    @test status === :exit_ok
    @test o.value == "the answer"
    # Final updates should still be drained even though the task is done
    @test o.data.progress ≈ 1.0
    @test o.data.text == "done"
end

@testset "tick returns :exit_nothing on worker exception" begin
    ch   = Channel{TW.ProgressUpdate}(64)
    flag = Threads.Atomic{Bool}(false)

    task = Threads.@spawn begin
        put!(ch, TW.ProgressUpdate(0.3, "about to fail"))
        error("boom")
    end
    # Wait for failure; wait() will rethrow, so swallow it
    try; wait(task); catch; end
    @test istaskdone(task)
    @test task.state === :failed

    o = make_progress(task, ch, flag)
    status = TW.tick(o)
    @test status === :exit_nothing
    @test o.value === nothing
end

@testset "cancellation: inject sets flag, worker observes it" begin
    ch   = Channel{TW.ProgressUpdate}(64)
    flag = Threads.Atomic{Bool}(false)

    cancelled_seen = Ref(false)
    task = Threads.@spawn begin
        for i in 1:1000
            if flag[]
                cancelled_seen[] = true
                return :stopped_early
            end
            sleep(0.01)
            put!(ch, TW.ProgressUpdate(i/1000, "i=$i"))
        end
        :ran_to_end
    end

    o = make_progress(task, ch, flag)

    # Let the worker run a bit, then inject :esc which sets the flag
    sleep(0.1)
    @test TW.inject(o, :esc) === :got_it
    @test flag[] == true

    # Worker should observe the flag and finish promptly with :stopped_early
    wait(task)
    @test istaskdone(task)
    @test cancelled_seen[] == true
    @test task.result === :stopped_early

    # tick should now report :exit_ok with the early result
    status = TW.tick(o)
    @test status === :exit_ok
    @test o.value === :stopped_early
end

@testset "inject ignores non-cancel keys" begin
    ch   = Channel{TW.ProgressUpdate}(64)
    flag = Threads.Atomic{Bool}(false)
    task = Threads.@spawn (sleep(60); nothing)
    o    = make_progress(task, ch, flag)

    @test TW.inject(o, :up) === :pass
    @test TW.inject(o, "a") === :pass
    @test TW.inject(o, :F1) === :pass
    @test flag[] == false   # flag not flipped

    # Ctrl-K is the documented alternative cancel key
    @test TW.inject(o, :ctrl_k) === :got_it
    @test flag[] == true

    schedule(task, InterruptException(); error=true)
end

@testset "register_tickable! / unregister_tickable!" begin
    scrdata = TW.TwScreenData()
    scr = TW.TwObj(scrdata, Val{:Screen})

    ch   = Channel{TW.ProgressUpdate}(8)
    flag = Threads.Atomic{Bool}(false)
    task = Threads.@spawn (sleep(60); nothing)
    o    = make_progress(task, ch, flag)

    @test isempty(scr.data.tickables)
    TW.register_tickable!(scr, o)
    @test length(scr.data.tickables) == 1
    @test scr.data.tickables[1] === o

    # Idempotent
    TW.register_tickable!(scr, o)
    @test length(scr.data.tickables) == 1

    TW.unregister_tickable!(scr, o)
    @test isempty(scr.data.tickables)

    # Removing something not registered is a no-op
    TW.unregister_tickable!(scr, o)
    @test isempty(scr.data.tickables)

    schedule(task, InterruptException(); error=true)
end

@testset "generic tick fallback returns :pass for non-ticking widgets" begin
    scrdata = TW.TwScreenData()
    scr = TW.TwObj(scrdata, Val{:Screen})
    @test TW.tick(scr) === :pass
end

println("\nAll progress unit tests passed.")
