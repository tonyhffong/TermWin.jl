# Headless unit tests for the optional (clearable) twcalendar. No TTY required —
# the calendar's TwCalendarData is built manually and the Ctrl-K Binding action is
# driven directly, exercising the "clear -> missing" accept path.
#
# Run:
#   julia --project=. test/calendar_clear_unit.jl

using Test
using TermWin
using Dates

const TW = TermWin

@testset "optional twcalendar clears with Ctrl-K" begin
    # An optional calendar exposes a Ctrl-K clear binding whose action accepts
    # `missing` (a distinct "no date" sentinel, ≠ a Date and ≠ nothing/cancel).
    o = TW.TwObj(TW.TwCalendarData(today(); optional = true), Val{:Calendar})
    o.value = today()
    clears = [b for b in TW.bindings(o) if :ctrl_k in b.keys]
    @test length(clears) == 1
    @test clears[1].action(o) == TW.Accept
    @test o.value === missing

    # Enter still accepts the cursor date as a Date.
    o.data.date = Date(2024, 3, 20)
    selects = [b for b in TW.bindings(o) if :enter in b.keys]
    @test length(selects) == 1
    @test selects[1].action(o) == TW.Accept
    @test o.value == Date(2024, 3, 20)
end

@testset "non-optional twcalendar has no clear binding" begin
    o = TW.TwObj(TW.TwCalendarData(today()), Val{:Calendar})   # optional defaults to false
    @test isempty([b for b in TW.bindings(o) if :ctrl_k in b.keys])
end
