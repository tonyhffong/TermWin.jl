# Headless unit tests for mouse corner-drag window resize.
#
# Same approach as test/window_raise_unit.jl: poke the mouse-event cache that
# readtoken fills, then drive the screen's inject directly — no TTY required,
# though a Notcurses session (planes + z-stack) is needed, so the whole set is
# skipped if initsession can't come up in this environment.
#
# Run:
#   julia --project=. test/window_resize_unit.jl

using Test
using TermWin

const TW = TermWin

function _press!(scr, y, x)
    TW._last_mouse_event[] = (:button1_pressed, x, y, nothing)
    TW.inject(scr, :KEY_MOUSE)
end

function _release!(scr, y, x)
    TW._last_mouse_event[] = (:button1_released, x, y, nothing)
    TW.inject(scr, :KEY_MOUSE)
end

function _motion!(scr, y, x)
    TW._last_mouse_event[] = (:motion, x, y, nothing)
    TW.inject(scr, :KEY_MOUSE_MOTION)
end

function _stack!(w_bottom, w_top)
    TW.raiseTwObject(w_bottom)
    TW.raiseTwObject(w_top)
end

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "window_resize_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        scr = rootTwScreen
        # Large enough that the two corner-tolerance zones never overlap, and
        # roomy enough above RESIZE_MIN_HEIGHT/RESIZE_MIN_WIDTH that drags can
        # shrink it without immediately hitting the floor.
        w1 = newTwPopup(
            scr, ["a", "b", "c", "d", "e", "f"];
            posy = 2, posx = 2, minwidth = 30, maxwidth = 30, title = "W1",
        )
        w2 = newTwPopup(scr, ["x", "y", "z"]; posy = 2, posx = 50, title = "W2")

        @testset "exact bottom-right corner press arms a :bottom_right resize" begin
            _stack!(w1, w2)
            _press!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            st = TW._resize_state[]
            @test st !== nothing
            @test st[1] === w1
            @test st[2] === :bottom_right
            _release!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            @test TW._resize_state[] === nothing
        end

        @testset "exact bottom-left corner press arms a :bottom_left resize" begin
            _stack!(w1, w2)
            _press!(scr, w1.ypos + w1.height - 1, w1.xpos)
            st = TW._resize_state[]
            @test st !== nothing
            @test st[1] === w1
            @test st[2] === :bottom_left
            _release!(scr, w1.ypos + w1.height - 1, w1.xpos)
        end

        @testset "tolerance: 2 chars horizontally / 1 char vertically from the corner still arms" begin
            _stack!(w1, w2)
            # bottom-right corner, nudged 2 left and 1 up — still within tolerance.
            _press!(scr, w1.ypos + w1.height - 2, w1.xpos + w1.width - 3)
            @test TW._resize_state[] !== nothing
            @test TW._resize_state[][2] === :bottom_right
            _release!(scr, w1.ypos + w1.height - 2, w1.xpos + w1.width - 3)
        end

        @testset "outside tolerance does not arm a resize" begin
            _stack!(w1, w2)
            # 3 chars left of the bottom-right corner: outside the 2-char horizontal tolerance.
            _press!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 4)
            @test TW._resize_state[] === nothing
            _release!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 4)
        end

        @testset "dragging bottom-right corner grows height/width, leaves xpos/ypos fixed" begin
            _stack!(w1, w2)
            oy, ox, oh, ow = w1.ypos, w1.xpos, w1.height, w1.width
            cy, cx = oy + oh - 1, ox + ow - 1
            _press!(scr, cy, cx)
            _motion!(scr, cy + 3, cx + 5)
            @test w1.height == oh + 3
            @test w1.width == ow + 5
            @test w1.ypos == oy
            @test w1.xpos == ox
            _release!(scr, cy + 3, cx + 5)
        end

        @testset "dragging bottom-left corner moves xpos, keeps right edge and ypos fixed" begin
            _stack!(w1, w2)
            oy, ox, oh, ow = w1.ypos, w1.xpos, w1.height, w1.width
            right_edge = ox + ow
            cy, cx = oy + oh - 1, ox
            _press!(scr, cy, cx)
            _motion!(scr, cy + 2, cx + 4) # drag corner right and down → shrinks width, grows height
            @test w1.height == oh + 2
            @test w1.width == ow - 4
            @test w1.xpos + w1.width == right_edge
            @test w1.ypos == oy
            _release!(scr, cy + 2, cx + 4)
        end

        @testset "resize floors at RESIZE_MIN_HEIGHT/RESIZE_MIN_WIDTH" begin
            _stack!(w1, w2)
            oy, ox, oh, ow = w1.ypos, w1.xpos, w1.height, w1.width
            cy, cx = oy + oh - 1, ox + ow - 1
            _press!(scr, cy, cx)
            _motion!(scr, cy - 100, cx - 100) # drag far up-left: shrink past the floors
            @test w1.height == TW.RESIZE_MIN_HEIGHT
            @test w1.width == TW.RESIZE_MIN_WIDTH
            @test w1.ypos == oy
            @test w1.xpos == ox
            _release!(scr, cy - 100, cx - 100)
            # restore w1's geometry for subsequent tests
            w1.desiredHeight = oh
            w1.desiredWidth = ow
            w1.desiredPosy = oy
            w1.desiredPosx = ox
            TW.relayout!(w1)
        end

        @testset "release clears resize state" begin
            _stack!(w1, w2)
            _press!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            @test TW._resize_state[] !== nothing
            _release!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            @test TW._resize_state[] === nothing
        end

        @testset "a window without a box is not resizable" begin
            w1.box = false
            _stack!(w1, w2)
            _press!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            @test TW._resize_state[] === nothing
            _release!(scr, w1.ypos + w1.height - 1, w1.xpos + w1.width - 1)
            w1.box = true
        end

        @testset "resizing a stacked layout keeps children edge-to-edge (no blank-row gaps)" begin
            # Regression: link_parent_child strips each child's box border once,
            # but relayout! re-resolved numeric desiredHeight border-inclusive, so
            # every formerly-boxed child grew by 2 rows per resize — inserting 2
            # blank rows between stacked widgets (ypos 0,1,2 → 0,3,6).
            v = TW.vstack(scr; title = "Form", height = 20, width = 40, posy = 2, posx = 2) do s
                TW.newTwEntry(s, String; key = :a, title = "A")
                TW.newTwEntry(s, String; key = :b, title = "B")
                TW.newTwEntry(s, String; key = :c, title = "C")
            end
            _stack!(w1, v)                                   # raise v to the top
            h_before = [c.height for c in v.data.widgets]
            y_before = [c.ypos   for c in v.data.widgets]
            cy, cx = v.ypos + v.height - 1, v.xpos + v.width - 1
            _press!(scr, cy, cx)
            _motion!(scr, cy + 4, cx + 6)                    # grow the window
            _release!(scr, cy + 4, cx + 6)
            @test v.height == 24                             # the outer window did resize
            @test [c.height for c in v.data.widgets] == h_before   # children unchanged
            @test [c.ypos   for c in v.data.widgets] == y_before   # still stacked tight
        end
    finally
        TW.endsession()
    end
end

println("window_resize_unit.jl: all tests passed")
