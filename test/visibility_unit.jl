# Headless unit tests for reactive section visibility (`visible_when`).
#
# A container list may carry a `visible_when = snap -> Bool` predicate. After each
# keystroke the root list re-evaluates it against the live form snapshot and flips
# the section's isVisible, collapsing/expanding the freed layout space and keeping
# focus off hidden fields. Same headless approach as test/window_resize_unit.jl:
# no TTY, but a Notcurses session (planes) is needed, so the set is skipped if
# initsession can't come up.
#
# Run:  julia --project=. test/visibility_unit.jl

using Test
using TermWin

const TW = TermWin

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "visibility_unit.jl: no Notcurses session available, skipping" err
end

# Build a form: a controlling entry (:mode), a section that is visible only when
# mode == "adv", and a footer entry AFTER the section (so its ypos reveals whether
# the section's space collapsed).
function build_form()
    scr = rootTwScreen
    mode = nothing
    adv = nothing
    threads = nothing
    footer = nothing
    v = TW.vstack(scr; form = true, height = 20, width = 50) do s
        mode = TW.newTwEntry(s, String; key = :mode, title = "Mode")
        adv = TW.vstack(s; visible_when = snap -> get(snap, :mode, "") == "adv") do a
            threads = TW.newTwEntry(a, Int; key = :threads, title = "Threads")
            TW.newTwEntry(a, String; key = :host, title = "Host")
        end
        footer = TW.newTwEntry(s, String; key = :footer, title = "Footer")
    end
    TW.draw(v)   # establishes default focus (as the real event loop does)
    (v, mode, adv, threads, footer)
end

if session_ok
    try
        @testset "starts hidden and space is collapsed" begin
            (v, mode, adv, threads, footer) = build_form()
            @test adv.isVisible == false                 # mode == "" ≠ "adv"
            # footer sits directly below the mode field — the section took no space.
            @test footer.ypos == mode.ypos + mode.height
        end

        @testset "becomes visible after the controlling field changes" begin
            (v, mode, adv, threads, footer) = build_form()
            collapsed_footer_y = footer.ypos

            # Simulate the user having typed "adv" into the mode field, then drive
            # one token through the root so the visibility hook fires.
            mode.value = "adv"
            TW.inject(v, :end)   # a harmless key; the hook runs regardless

            @test adv.isVisible == true
            @test footer.ypos > collapsed_footer_y       # section reclaimed its rows
            @test footer.ypos == adv.ypos + adv.height    # footer now sits below it
        end

        @testset "toggling back re-collapses the space" begin
            (v, mode, adv, threads, footer) = build_form()
            collapsed_footer_y = footer.ypos

            mode.value = "adv"
            TW.inject(v, :end)
            @test adv.isVisible == true

            mode.value = "basic"
            TW.inject(v, :end)
            @test adv.isVisible == false
            @test footer.ypos == collapsed_footer_y       # back to the collapsed layout
        end

        @testset "focus never sticks on a hidden field" begin
            (v, mode, adv, threads, footer) = build_form()
            # reveal the section and move focus into it
            mode.value = "adv"
            TW.inject(v, :end)
            TW.deep_unfocus(TW.lowest_widget(v))
            TW.deep_focus(threads)
            @test TW.lowest_widget(v) === threads

            # hide it again → focus must leave the now-hidden field
            mode.value = "basic"
            TW.inject(v, :end)
            @test adv.isVisible == false
            @test TW._is_effectively_visible(TW.lowest_widget(v))
        end

        @testset "hidden section values are still collected (keep-all)" begin
            (v, mode, adv, threads, footer) = build_form()
            threads.value = 8
            @test adv.isVisible == false                 # section hidden
            snap = TW.collect_form_values(v)
            @test haskey(snap, :threads)                 # hidden field still contributes
            @test snap[:threads] == 8
        end
    finally
        TW.endsession()
    end
end

println("visibility_unit.jl: all tests passed")
