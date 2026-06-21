# Headless unit tests for mouse click-to-raise and title-bar drag arming.
#
# Two non-overlapping popups are placed on the screen; the lower one is then
# "clicked" by poking the mouse-event cache (the same tuple readtoken fills) and
# driving the screen's inject directly — no TTY interaction required, though a
# Notcurses session (planes + z-stack) is needed, so the whole set is skipped if
# initsession can't come up in this environment.
#
# Run:
#   julia --project=. test/window_raise_unit.jl

using Test
using TermWin

const TW = TermWin

# Simulate a left-button press at screen (row=y, col=x) and route it to the screen.
function _press!(scr, y, x)
    TW._last_mouse_event[] = (:button1_pressed, x, y, nothing)
    TW.inject(scr, :KEY_MOUSE)
end

# Simulate the matching release (ends any armed drag).
function _release!(scr, y, x)
    TW._last_mouse_event[] = (:button1_released, x, y, nothing)
    TW.inject(scr, :KEY_MOUSE)
end

# Full click = press + release.
function _click!(scr, y, x)
    r = _press!(scr, y, x)
    _release!(scr, y, x)
    r
end

# Force a known z-order: w_bottom lowest, w_top highest (and focused).
function _stack!(w_bottom, w_top)
    TW.raiseTwObject(w_bottom)
    TW.raiseTwObject(w_top)
end

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "window_raise_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        scr = rootTwScreen
        # Created W1 first, W2 second → W2 starts on top.
        w1 = newTwPopup(scr, ["a", "b", "c"]; posy = 2, posx = 2,  title = "W1")
        w2 = newTwPopup(scr, ["x", "y", "z"]; posy = 2, posx = 40, title = "W2")

        @testset "click title of lower window raises it to top" begin
            _stack!(w1, w2)
            @test scr.data.objects[end] === w2          # precondition: W2 on top
            r = _click!(scr, w1.ypos, w1.xpos + 2)       # W1 title-bar row (rely==0)
            @test r === Handled
            @test scr.data.objects[end] === w1           # W1 now on top
            @test scr.data.focus == length(scr.data.objects)
        end

        @testset "click body of lower window raises it to top" begin
            _stack!(w1, w2)
            _click!(scr, w1.ypos + 2, w1.xpos + 5)       # interior (not title)
            @test scr.data.objects[end] === w1
        end

        @testset "click left border of lower window raises it to top" begin
            _stack!(w1, w2)
            _click!(scr, w1.ypos + 2, w1.xpos)           # left edge column
            @test scr.data.objects[end] === w1
        end

        @testset "click bottom border of lower window raises it to top" begin
            _stack!(w1, w2)
            _click!(scr, w1.ypos + w1.height - 1, w1.xpos + 3)
            @test scr.data.objects[end] === w1
        end

        @testset "title-bar press arms a drag, release clears it" begin
            _stack!(w1, w2)
            _press!(scr, w1.ypos, w1.xpos + 2)           # press, no release yet
            st = TW._drag_state[]
            @test st !== nothing
            @test st[1] === w1                            # captured widget
            _release!(scr, w1.ypos, w1.xpos + 2)
            @test TW._drag_state[] === nothing
        end

        @testset "non-title click does not arm a drag" begin
            _stack!(w1, w2)
            _press!(scr, w1.ypos + 2, w1.xpos + 5)        # body press
            @test TW._drag_state[] === nothing
            _release!(scr, w1.ypos + 2, w1.xpos + 5)
        end
    finally
        TW.endsession()
    end
end

println("window_raise_unit.jl: all tests passed")
