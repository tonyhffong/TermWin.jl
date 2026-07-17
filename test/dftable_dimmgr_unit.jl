# Headless test for the DfTable dimension manager (the `P` binding).
#
# `P` opens an editable table of calculated dimensions — an `active` toggle (is it
# an applied pivot?), a `name`, and a `spec` edited via a popup spec entry. This
# drives the underlying `_dt_dims_dataframe` / `_dt_apply_dims!` directly (not the
# TTY), plus the generic edit-table `popup_editor` / Bool-cell additions.
#
# Run:  julia --project=. test/dftable_dimmgr_unit.jl

using Test
using TermWin, DataFrames

const _MDF = DataFrame(region = ["E", "E", "W"], score = [10.0, 20.0, 30.0])
const _BAND = "discretize(score, [0.0, 15.0, 30.0])"

# A table with one active user dimension (:band) over the :region pivot.
function _mktable()
    obj = TermWin.newTwDfTable(rootTwScreen, _MDF; pivots = [:region])
    TermWin._dt_add_dimension!(obj, "band", _BAND)
    obj.data.pivots = [:region, :band]
    TermWin._dt_rebuild_tree!(obj)
    obj
end

session_ok = false
try
    TermWin.initsession()
    global session_ok = true
catch err
    @warn "dftable_dimmgr_unit.jl: no Notcurses session available, skipping" err
end

if session_ok
    try
        @testset "manager DataFrame is name + spec (no active/order)" begin
            obj = _mktable()
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            @test Set(names(df)) == Set(["name", "spec"])   # editor only, no `active`
            i = findfirst(==("band"), df.name)
            @test i !== nothing
            @test occursin("discretize", df.spec[i])
            @test kinds["band"] == :safe
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "add a dimension (defined, NOT auto-applied as a pivot)" begin
            obj = _mktable()
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            push!(df, ("q", "discretize(score, ngroups=2)"))
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)
            @test haskey(obj.data.calcpivots, :q)
            @test :q ∉ obj.data.pivots           # defining does not apply it — that's `p`
            @test obj.data.pivots == [:region, :band]   # existing pivots untouched
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "blank name deletes the dim + prunes it from applied pivots" begin
            obj = _mktable()
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            df.name[findfirst(==("band"), df.name)] = ""
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)
            @test !haskey(obj.data.calcpivots, :band)
            @test :band ∉ obj.data.pivots         # applied pivot pruned
            @test :region in obj.data.pivots      # real-column pivot kept
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "rename a dim prunes the old name from applied pivots" begin
            obj = _mktable()
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            df.name[findfirst(==("band"), df.name)] = "band2"
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)
            @test haskey(obj.data.calcpivots, :band2)
            @test !haskey(obj.data.calcpivots, :band)
            @test :band ∉ obj.data.pivots         # old name pruned
            @test :band2 ∉ obj.data.pivots        # renamed dim is re-applied via `p`
            @test :region in obj.data.pivots
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "edit a spec re-parses (untrusted)" begin
            obj = _mktable()
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            df.spec[findfirst(==("band"), df.name)] = "discretize(score, ngroups=3)"
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)
            @test obj.data.calcpivots[:band] isa TermWin.SafeDimSpec
            @test occursin("ngroups=3", obj.data.calcpivots[:band].source)
            @test :band in obj.data.pivots        # still applied (name unchanged)
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "safety: invalid / collision / duplicate rejected, state unchanged" begin
            obj = _mktable()
            before_calc = copy(obj.data.calcpivots)
            before_piv  = copy(obj.data.pivots)

            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            push!(df, ("x", "Base.run(`ls`)"))               # eval-shaped → rejected
            @test_throws Exception TermWin._dt_apply_dims!(obj, df, kinds, payloads)
            @test obj.data.calcpivots == before_calc          # unchanged
            @test obj.data.pivots == before_piv

            (df2, k2, p2) = TermWin._dt_dims_dataframe(obj)
            push!(df2, ("score", "discretize(score,[0.0])"))  # real-column name
            @test_throws Exception TermWin._dt_apply_dims!(obj, df2, k2, p2)

            (df3, k3, p3) = TermWin._dt_dims_dataframe(obj)
            push!(df3, ("band", "discretize(score, ngroups=2)"))  # duplicate name
            @test_throws Exception TermWin._dt_apply_dims!(obj, df3, k3, p3)
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "unchanged trusted Expr dim is preserved (not downgraded)" begin
            obj = TermWin.newTwDfTable(rootTwScreen, _MDF;
                calcpivots = Dict{Symbol,Any}(
                    :eband => :( discretize(:score, [0.0, 15.0, 30.0]) )))
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            @test kinds["eband"] == :expr
            orig = obj.data.calcpivots[:eband]
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)   # no edits
            @test obj.data.calcpivots[:eband] === orig          # same Expr object kept
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "Function dim is :func (read-only) and preserved" begin
            obj = TermWin.newTwDfTable(rootTwScreen, _MDF;
                calcpivots = Dict{Symbol,Any}(:fn => (d -> d.score)))
            (df, kinds, payloads) = TermWin._dt_dims_dataframe(obj)
            i = findfirst(==("fn"), df.name)
            @test kinds["fn"] == :func
            @test df.spec[i] == "<function>"
            orig = obj.data.calcpivots[:fn]
            TermWin._dt_apply_dims!(obj, df, kinds, payloads)   # no edits
            @test obj.data.calcpivots[:fn] === orig             # preserved
            TermWin.unregisterTwObj(rootTwScreen, obj)
        end

        @testset "edit-table: pin_col floats to top + Shift reorder + Space toggle" begin
            df = DataFrame(on = [false, true, false, true], name = ["a", "b", "c", "d"])
            cols = TwEditTableCol[
                TwEditTableCol(:on,   "On",   4, true, Bool,   nothing, false, nothing),
                TwEditTableCol(:name, "Name", 8, true, String, nothing, false, nothing),
            ]
            et = TermWin.newTwEditTable(rootTwScreen, df, cols;
                pin_col = :on, reorderable = true)
            # construction floats the pinned rows (b, d) to the top, order preserved
            @test et.data.df.name == ["b", "d", "a", "c"]

            # Shift-Down reorders within the pinned group: b,d → d,b
            et.data.currentRow = 1
            TermWin._et_reorder!(et, 1)
            @test et.data.df.name[1:2] == ["d", "b"]
            @test et.data.currentRow == 2

            # reordering across the pin boundary is refused
            et.data.currentRow = 2                 # b (pinned); row 3 is unpinned
            TermWin._et_reorder!(et, 1)
            @test et.data.df.name[2] == "b"
            @test et.data.currentRow == 2

            # Space toggles the current row's pin and re-floats
            et.data.currentRow = 1; et.data.currentCol = 1   # d (pinned)
            TermWin.inject(et, " ")
            @test et.data.df.name[1] == "b"        # only b remains pinned, on top
            @test et.data.df.on[findfirst(==("d"), et.data.df.name)] == false

            # typing into the pin column does nothing (it's Space-toggle only)
            et.data.currentRow = 1; et.data.currentCol = 1
            before = et.data.df.on[1]
            TermWin.inject(et, "f")
            @test et.data.df.on[1] == before
            TermWin.unregisterTwObj(rootTwScreen, et)
        end

        @testset "edit-table: row_style hook is applied per row" begin
            df = DataFrame(name = ["x", "y"])
            cols = [TwEditTableCol(:name, "Name", 8, true, String, nothing)]
            style = (d, r) -> d.name[r] == "y" ? COLOR_PAIR(29) : nothing
            et = TermWin.newTwEditTable(rootTwScreen, df, cols; row_style = style)
            @test et.data.row_style !== nothing
            @test et.data.row_style(et.data.df, 2) == COLOR_PAIR(29)
            @test et.data.row_style(et.data.df, 1) === nothing
            TermWin.unregisterTwObj(rootTwScreen, et)
        end

        @testset "edit-table: Bool rendering + popup_editor cell (generic)" begin
            df = DataFrame(flag = [true, false], note = ["a", "b"])
            opened = Ref(false)
            ed = (scr, cur) -> (opened[] = true; "EDITED")
            cols = TwEditTableCol[
                TwEditTableCol(:flag, "Flag", 6,  true, Bool,   nothing, false, nothing),
                TwEditTableCol(:note, "Note", 12, true, String, nothing, false, ed),
            ]
            @test TermWin._et_cell_to_buf(true,  cols[1]) == "true"
            @test TermWin._et_cell_to_buf(false, cols[1]) == "false"

            et = TermWin.newTwEditTable(rootTwScreen, df, cols)
            et.data.currentCol = 2
            TermWin.inject(et, "x")               # printable into a popup-editor cell → opens it
            @test opened[] == true
            @test et.data.df[1, :note] == "EDITED"
            TermWin.unregisterTwObj(rootTwScreen, et)
        end
    finally
        TermWin.endsession()
    end
end

println("dftable_dimmgr_unit.jl: done.")
