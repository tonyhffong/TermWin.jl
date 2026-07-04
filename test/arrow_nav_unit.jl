# Headless unit tests for arrow-key navigation across a layout.
#
# Two regressions are covered:
#   1. Arrow-key geometric navigation must NOT descend into a hidden
#      (`visible_when`-collapsed) container — Tab already skips it, and geometric
#      nav now matches (geometric_filter gates on isVisible before recursing).
#   2. A horizontal arrow at the text edge of an entry must hand off to the
#      layout so focus crosses to the sibling column (entry yields Ignored at the
#      boundary instead of beeping and swallowing the key).
#
# Same headless approach as test/visibility_unit.jl: no TTY, but a Notcurses
# session (planes) is needed, so the set is skipped if initsession can't come up.
#
# Run:  julia --project=. test/arrow_nav_unit.jl

using Test
using TermWin

const TW = TermWin

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "arrow_nav_unit.jl: no Notcurses session available, skipping" err
end

# Vertical form with a hidden section (threads/host) between two visible entries.
function build_hidden_form()
    scr = rootTwScreen
    mode = nothing; adv = nothing; threads = nothing; host = nothing; footer = nothing
    v = TW.vstack(scr; form = true, height = 20, width = 50) do s
        mode = TW.newTwEntry(s, String; key = :mode, title = "Mode")
        adv = TW.vstack(s; visible_when = snap -> get(snap, :mode, "") == "adv") do a
            threads = TW.newTwEntry(a, Int; key = :threads, title = "Threads")
            host = TW.newTwEntry(a, String; key = :host, title = "Host")
        end
        footer = TW.newTwEntry(s, String; key = :footer, title = "Footer")
    end
    TW.draw(v)
    (v, mode, adv, threads, host, footer)
end

# Two side-by-side columns, one entry each.
function build_columns()
    scr = rootTwScreen
    left = nothing; right = nothing
    h = TW.hstack(scr; height = 10, width = 50) do hh
        TW.vstack(hh) do l
            left = TW.newTwEntry(l, String; key = :left, title = "L")
        end
        TW.vstack(hh) do r
            right = TW.newTwEntry(r, String; key = :right, title = "R")
        end
    end
    TW.draw(h)
    (h, left, right)
end

if session_ok
    try
        @testset "geometric_filter skips hidden section leaves" begin
            (v, mode, adv, threads, host, footer) = build_hidden_form()
            @test adv.isVisible == false
            # Collect every focusable leaf the arrow navigator can see.
            found = Any[]
            TW.geometric_filter(v, _ -> 0, 0, 0, found, false, 999999)
            widgets = [cw for (cw, _) in found]
            @test mode in widgets
            @test footer in widgets
            @test !(threads in widgets)   # hidden — must not be a candidate
            @test !(host in widgets)
        end

        @testset "arrow-down over a hidden section lands on the footer" begin
            (v, mode, adv, threads, host, footer) = build_hidden_form()
            @test TW.lowest_widget(v) === mode   # default focus on first field
            TW.inject(v, :down)
            # Without the fix this could land on `threads` inside the hidden adv.
            @test TW.lowest_widget(v) === footer
        end

        @testset "revealed section becomes reachable by arrow again" begin
            (v, mode, adv, threads, host, footer) = build_hidden_form()
            mode.value = "adv"
            TW.inject(v, :end)            # fire the visibility hook
            @test adv.isVisible == true
            found = Any[]
            TW.geometric_filter(v, _ -> 0, 0, 0, found, false, 999999)
            widgets = [cw for (cw, _) in found]
            @test threads in widgets      # now a valid candidate
        end

        @testset "right arrow at the edge crosses to the sibling column" begin
            (h, left, right) = build_columns()
            @test TW.lowest_widget(h) === left
            # Empty buffer ⇒ cursor is already at the right edge, so the entry
            # yields the key and the hstack navigates rightward.
            TW.inject(h, :right)
            @test TW.lowest_widget(h) === right
        end

        @testset "left arrow at the edge crosses back" begin
            (h, left, right) = build_columns()
            TW.deep_unfocus(TW.lowest_widget(h))
            TW.deep_focus(right)
            @test TW.lowest_widget(h) === right
            TW.inject(h, :left)
            @test TW.lowest_widget(h) === left
        end
    finally
        TW.endsession()
    end
end

println("arrow_nav_unit.jl: all tests passed")
