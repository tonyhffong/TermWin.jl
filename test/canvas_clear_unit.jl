# Headless regression: draw must clear the canvas so shrinking content leaves no
# stale cells behind.
#
# Two bugs this guards against:
#   * A DfTable given a smaller frame (setvalue!) used to leave the old, longer
#     frame's rows on screen — draw(::TwDfTableData) painted fewer rows without
#     first erasing its window.
#   * A layout (TwList) redrawn after a child shrank/collapsed used to bleed the
#     old content, because children paint onto the canvas pad and nothing cleared
#     the pad between frames (werase only cleared the visible plane).
#
# Run:  julia --project=. test/canvas_clear_unit.jl

using Test
using TermWin, DataFrames
import TermWin.NC

const TW = TermWin

# Text of a plane/pad row, trailing blanks stripped ("" for an all-blank row).
function _rowtext(win, y, w)
    p = NC.LibNotcurses.ncplane_contents(win.ptr, y, 0, 1, w)
    p == C_NULL ? "" : rstrip(unsafe_string(p))
end

session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "canvas_clear_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        big = DataFrame(k = 1:10, v = (1:10) .* 100)
        small = DataFrame(k = 1:2, v = [11, 22])

        @testset "embedded DfTable in a layout: shrinking the frame clears old rows" begin
            tbl = nothing
            v = TW.vstack(rootTwScreen; title = "V", height = 18, width = 40) do s
                tbl = TW.newTwDfTable(s, big)
            end
            TW.draw(v); NC.render(TW.nc_context)
            # sanity: the big frame's last rows are present on the pad
            @test any(occursin("900", _rowtext(v.data.pad, y, 38)) for y in 0:13)

            TW.setvalue!(tbl, small)
            TW.draw(v); NC.render(TW.nc_context)
            # every pad row must be free of the old frame's large values
            for y in 0:13
                txt = _rowtext(v.data.pad, y, 38)
                @test !occursin("300", txt)
                @test !occursin("900", txt)
                @test !occursin("1,000", txt)
            end
            # and the two new rows are there
            @test any(occursin("11", _rowtext(v.data.pad, y, 38)) for y in 0:13)

            TW.unregisterTwObj(rootTwScreen, v)
        end

        @testset "top-level DfTable (own plane): shrinking the frame clears old rows" begin
            tbl = TW.newTwDfTable(rootTwScreen, big; height = 16, width = 36)
            TW.draw(tbl); NC.render(TW.nc_context)
            @test any(occursin("900", _rowtext(tbl.window, y, tbl.width)) for y in 0:15)

            TW.setvalue!(tbl, small)
            TW.draw(tbl); NC.render(TW.nc_context)
            for y in 0:15
                txt = _rowtext(tbl.window, y, tbl.width)
                @test !occursin("300", txt)
                @test !occursin("900", txt)
                @test !occursin("1,000", txt)
            end

            TW.unregisterTwObj(rootTwScreen, tbl)
        end

        @testset "empty DataFrame renders without crashing" begin
            # A 0-row frame (e.g. a live widget whose query returned nothing)
            # used to kill updateTableDimensions with maximum() over an empty
            # datalist. Cover construction with an empty frame and the
            # populated -> empty -> populated setvalue! round-trip.
            empty0 = DataFrame(k = Int[], v = Int[])

            tbl = TW.newTwDfTable(rootTwScreen, empty0; height = 12, width = 36,
                                  showRoot = false)
            TW.draw(tbl); NC.render(TW.nc_context)
            # header still shows, no rows
            @test any(occursin("k", _rowtext(tbl.window, y, tbl.width)) for y in 0:11)
            TW.unregisterTwObj(rootTwScreen, tbl)

            tbl2 = TW.newTwDfTable(rootTwScreen, big; height = 12, width = 36,
                                   showRoot = false)
            TW.draw(tbl2); NC.render(TW.nc_context)
            TW.setvalue!(tbl2, empty0)
            TW.draw(tbl2); NC.render(TW.nc_context)
            for y in 0:11   # old rows must be gone
                @test !occursin("900", _rowtext(tbl2.window, y, tbl2.width))
            end
            TW.setvalue!(tbl2, big)
            TW.draw(tbl2); NC.render(TW.nc_context)
            @test any(occursin("900", _rowtext(tbl2.window, y, tbl2.width)) for y in 0:11)
            TW.unregisterTwObj(rootTwScreen, tbl2)
        end
    finally
        TW.endsession()
    end
end

println("canvas_clear_unit.jl: all tests passed")
