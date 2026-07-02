# Headless unit test for click-to-focus routing inside a scrolled layout.
#
# Regression: the root-list mouse router converted a click to window-relative
# coordinates but never added the list's scroll offset (canvaslocy/canvaslocx),
# while geometric_filter compares against child rectangles in CANVAS space. When
# a layout's canvas exceeds the viewport and is scrolled (e.g. a large embedded
# table pushes the content past the window), clicks mapped to the wrong canvas
# row/column and focused the wrong widget — the table "stole" clicks meant for a
# sibling. See src/twlist.jl (the :KEY_MOUSE / button1_pressed branch).
#
# Run:  julia --project=. test/list_mouse_click_unit.jl

using Test
using TermWin, DataFrames

const TW = TermWin
import TermWin.NC

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "list_mouse_click_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        scr = rootTwScreen
        df = DataFrame(k = 1:30, v = (1:30) .^ 2)

        tbl = nothing
        tr = nothing
        # Auto heights make the vstack canvas taller than the 16-row viewport, so
        # the layout is genuinely scrollable.
        v = TW.vstack(scr; title = "V", height = 16, width = 50) do s
            tbl = TW.newTwDfTable(s, df)
            tr = TW.newTwTree(s, Dict("target" => 1))
        end
        TW.draw(v)

        @testset "scrolled layout routes a click into canvas space (no steal)" begin
            @test v.data.canvasheight > v.height          # actually scrollable
            @test tr.window.yloc > tbl.window.yloc         # tree is below the table

            # Scroll so the tree sits a few rows below the window content origin.
            C = tr.window.yloc - 3
            v.data.canvaslocy = C

            plane = NC.yx(v.window)
            target_canvas_row = tr.window.yloc + 1         # a row clearly inside the tree
            screen_y = Int(plane.y) + 1 + (target_canvas_row - C)   # +1 = top border
            screen_x = Int(plane.x) + 3

            TW._last_mouse_event[] = (:button1_pressed, screen_x, screen_y, nothing)
            TW.inject(v, :KEY_MOUSE)

            @test tr.hasFocus            # the click landed on the tree...
            @test !tbl.hasFocus          # ...not stolen by the table above it
        end
    finally
        TW.endsession()
    end
end

println("list_mouse_click_unit.jl: all tests passed")
