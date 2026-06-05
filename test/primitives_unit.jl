# Automated unit tests for the widget-authoring primitives.
# No TTY required — all of these are pure data/logic, exercised headless.
#
# Run:
#   julia --project=. test/primitives_unit.jl

using Test
using TermWin

const TW = TermWin

@testset "InjectResult enum" begin
    # Every widget's inject now returns one of these (the Symbol→InjectResult
    # shim has been retired; the event loop dispatches on the enum directly).
    @test TW.Handled isa TW.InjectResult
    @test (TW.Handled, TW.Ignored, TW.Accept, TW.Cancel) ==
          (TW.Handled, TW.Ignored, TW.Accept, TW.Cancel)
    @test length(instances(TW.InjectResult)) == 4
end

@testset "Result{T} + unwrap" begin
    @test TW.unwrap(TW.Ok(42)) == 42
    @test TW.unwrap(TW.Ok("hi")) == "hi"
    @test TW.unwrap(TW.Cancelled()) === nothing
    @test TW.isok(TW.Ok(1))
    @test !TW.isok(TW.Cancelled())
    @test_throws ErrorException TW.unwrap(TW.Failed(ErrorException("boom")))
    @test TW.Ok(3) isa TW.Result{Int}
end

@testset "ScrollState / clamp_view! invariant" begin
    # The contract: cursor lands in 1:n and stays inside [top, top+vp-1], top>=1.
    for n in (0, 1, 5, 20), vp in (1, 3, 7), c0 in (-3, 1, 4, 25), t0 in (1, 10)
        s = TW.ScrollState(t0, 1, c0)
        TW.clamp_view!(s, n, vp)
        nn = max(1, n)
        @test 1 <= s.cursor <= nn
        @test s.top >= 1
        @test s.top <= s.cursor
        @test s.cursor <= s.top + vp - 1
    end
end

@testset "ScrollState move/page/scroll_left" begin
    s = TW.ScrollState()           # top=1 left=1 cursor=1
    TW.move_cursor!(s, 1, 10, 4)
    @test s.cursor == 2 && s.top == 1
    TW.move_cursor!(s, 5, 10, 4)   # cursor 7 -> top follows
    @test s.cursor == 7
    @test s.top == 4               # 7 - 4 + 1
    TW.move_cursor!(s, -100, 10, 4)
    @test s.cursor == 1 && s.top == 1
    # paging
    s2 = TW.ScrollState(1, 1, 1)
    TW.page!(s2, 1, 100, 10)
    @test s2.cursor == 11
    # horizontal
    s3 = TW.ScrollState()
    TW.scroll_left!(s3, 5, 3)      # clamp to maxleft
    @test s3.left == 3
    TW.scroll_left!(s3, -100, 3)
    @test s3.left == 1
    # visibility predicate
    @test TW.visible(TW.ScrollState(4, 1, 6), 6, 5)
    @test !TW.visible(TW.ScrollState(4, 1, 6), 1, 5)
end

@testset "Theme tokens resolve" begin
    # default theme tokens exist and resolve to usable attrs / glyph
    for tok in (:selection_focused, :selection_unfocused, :header, :divider, :negative, :emphasis)
        @test TW.theme(tok) isa TW.TwAttr
    end
    @test TW.theme(:focus_indicator) == '▶'
    @test_throws ErrorException TW.theme(:does_not_exist)

    # swappable; refresh_theme! keeps the active name
    TW.set_theme!(:high_contrast)
    @test TW.current_theme[].name === :high_contrast
    @test TW.theme(:selection_focused) isa TW.TwAttr
    TW.refresh_theme!()
    @test TW.current_theme[].name === :high_contrast   # name preserved across refresh
    TW.set_theme!(:default)
    @test TW.current_theme[].name === :default
    @test_throws ErrorException TW.set_theme!(:nope)
end

@testset "Typed rows + tree_nav" begin
    # Build a small tree:
    #   a            (depth 1)
    #     a1         (depth 2)
    #     a2         (depth 2)
    #   b            (depth 1)
    #     b1         (depth 2)
    mkrow(name, stack) = TW.TreeRow(name, "", "", stack, :single, Int[])
    rows = TW.TreeRow[
        mkrow("a",  Any["a"]),
        mkrow("a1", Any["a", "a1"]),
        mkrow("a2", Any["a", "a2"]),
        mkrow("b",  Any["b"]),
        mkrow("b1", Any["b", "b1"]),
    ]
    @test TW.depth(rows[2]) == 2
    @test TW.parent_prefix(rows[2]) == Any["a"]

    # from a2 (idx 3): parent -> a (idx 1)
    @test TW.tree_nav(rows, 3, :parent) == (1, true)
    # from a2: prev_sibling -> a1 (idx 2)
    @test TW.tree_nav(rows, 3, :prev_sibling) == (2, true)
    # from a1: next_sibling -> a2 (idx 3)
    @test TW.tree_nav(rows, 2, :next_sibling) == (3, true)
    # from a2: next_sibling -> none (b is shallower) => no move
    @test TW.tree_nav(rows, 3, :next_sibling) == (3, false)
    # from a (idx1): parent -> none (root)
    @test TW.tree_nav(rows, 1, :parent) == (1, false)
    # from a (idx1): next_sibling -> b (idx 4)
    @test TW.tree_nav(rows, 1, :next_sibling) == (4, true)
    # b1 is a different subtree: a1.next_sibling must not jump to b1
    @test TW.tree_nav(rows, 2, :next_sibling) == (3, true)
end

@testset "Bindings generate footer + help + dispatch" begin
    # A throwaway widget type with a binding table.
    data = TW.TwScreenData()              # any data; we just need a TwObj
    o = TW.TwObj(data, Val{:BindTest})
    o.value = 0

    # Define bindings for this object's type via a method on a closure-captured table.
    binds = [
        TW.Binding([:up],    "up",     scope=:global, action = w->(w.value -= 1; TW.Handled)),
        TW.Binding([:down],  "down",   scope=:global, action = w->(w.value += 1; TW.Handled)),
        TW.Binding([:enter], "select", scope=:global, action = w->TW.Accept),
        TW.Binding([:F7],    "save",   scope=:global, when = w->false, action = w->TW.Handled),
    ]
    # Monkey-patch bindings(o) for the :BindTest type just for this test.
    @eval TW bindings(::$(typeof(o))) = $binds

    @test TW.footer(o) == "↑:up  ↓:down  Enter:select"   # F7 hidden by when=false
    help = TW.helptext_from_bindings(o)
    @test occursin("Enter", help) && occursin("select", help)
    @test !occursin("save", help)                         # guarded out

    @test TW.inject_via_table(o, :down) === TW.Handled
    @test o.value == 1
    @test TW.inject_via_table(o, :enter) === TW.Accept
    @test TW.inject_via_table(o, :F7) === TW.Ignored      # when=false → not matched
    @test TW.inject_via_table(o, :pageup) === TW.Ignored  # unknown key

    # keylabel formatting
    @test TW.keylabel(:ctrl_n) == "Ctrl-N"
    @test TW.keylabel(:alt_c) == "Alt-c"
    @test TW.keylabel(:shift_F6) == "Shift-F6"
    @test TW.keylabel(:up) == "↑"
end

@testset "Observable set!/on/off" begin
    obs = TW.Observable(0)
    seen = Int[]
    f = TW.on(obs) do v
        push!(seen, v)
    end
    TW.set!(obs, 1)
    TW.set!(obs, 2)
    @test TW.getvalue(obs) == 2
    @test seen == [1, 2]
    TW.off(f, obs)
    TW.set!(obs, 3)
    @test seen == [1, 2]              # no longer notified
    @test TW.getvalue(obs) == 3
end

@testset "Popup adopts ScrollState (headless)" begin
    # Build the data object directly so no TTY/plane is required.
    o = TW.TwObj(TW.TwPopupData(["a", "b", "c", "d", "e", "f"]), Val{:Popup})
    o.height = 4
    o.borderSizeV = 1                       # viewport = height - 2*border = 2

    @test TW.popup_count(o) == 6
    @test TW.popup_viewport(o) == 2
    @test o.data.scroll.cursor == 1 && o.data.scroll.top == 1

    # Move down past the viewport: top follows the cursor.
    TW.move_cursor!(o.data.scroll, 4, TW.popup_count(o), TW.popup_viewport(o))
    @test o.data.scroll.cursor == 5
    @test o.data.scroll.top == 4            # 5 - 2 + 1

    # Simulate a terminal resize that shrinks the viewport; clamp_scroll! (the
    # override popup previously lacked) keeps the cursor visible.
    o.height = 3                            # viewport now 1
    TW.clamp_scroll!(o)
    @test TW.visible(o.data.scroll, o.data.scroll.cursor, TW.popup_viewport(o))
    @test 1 <= o.data.scroll.top <= o.data.scroll.cursor
end

@testset "Tree adopts TreeRow + tree_nav (headless)" begin
    # tree_data is a pure function (no window), so we can build a real datalist
    # and exercise the converted data layer + shared navigation end-to-end.
    d = Dict("a" => [10, 20], "b" => 99)
    list = TW.TreeRow[]
    osm = Dict{Any,Bool}(Any[] => true, Any["a"] => true)   # expand root + "a"
    TW.tree_data(d, "root", list, osm, Any[], Int[], true)

    @test eltype(list) === TW.TreeRow
    @test list isa Vector{TW.TreeRow}

    # Expected flattened order (string keys are sorted):
    #   1 root          stack []        depth 0
    #   2 "a"  (vector) stack ["a"]     depth 1
    #   3 [1]=10        stack ["a",1]   depth 2
    #   4 [2]=20        stack ["a",2]   depth 2
    #   5 "b"=99        stack ["b"]     depth 1
    @test length(list) == 5
    @test TW.depth(list[1]) == 0
    @test TW.depth(list[3]) == 2
    @test list[2].expandhint == :open          # "a" is an expanded container
    @test list[2].skiplines isa Vector{Int}

    # Navigation over the real rows:
    @test TW.tree_nav(list, 3, :parent)       == (2, true)   # [a,1] -> "a"
    @test TW.tree_nav(list, 3, :next_sibling) == (4, true)   # [a,1] -> [a,2]
    @test TW.tree_nav(list, 4, :next_sibling) == (4, false)  # last child, no move
    @test TW.tree_nav(list, 4, :prev_sibling) == (3, true)   # [a,2] -> [a,1]
    @test TW.tree_nav(list, 2, :next_sibling) == (5, true)   # "a" -> "b"
    @test TW.tree_nav(list, 2, :parent)       == (1, true)   # "a" -> root
    @test TW.tree_nav(list, 1, :parent)       == (1, false)  # root has no parent
end

@testset "Calendar bindings (headless)" begin
    using Dates
    # Build the data object directly; inject_via_table runs the binding actions
    # without touching o.window (refresh only happens in inject, which we bypass).
    o = TW.TwObj(TW.TwCalendarData(Date(2026, 6, 15)), Val{:Calendar})
    o.data.ncalStyle = true   # newTwCalendar sets this; the raw ctor defaults false

    # Pure date-transform commands (String tokens) dispatch through the table.
    @test TW.inject_via_table(o, "d") === TW.Handled
    @test o.data.date == Date(2026, 6, 16)
    TW.inject_via_table(o, "D")
    @test o.data.date == Date(2026, 6, 15)
    TW.inject_via_table(o, "w");  @test o.data.date == Date(2026, 6, 22)
    TW.inject_via_table(o, "W");  @test o.data.date == Date(2026, 6, 15)
    TW.inject_via_table(o, "m");  @test o.data.date == Date(2026, 7, 15)
    TW.inject_via_table(o, "M");  @test o.data.date == Date(2026, 6, 15)
    TW.inject_via_table(o, "q");  @test o.data.date == Date(2026, 9, 15)
    TW.inject_via_table(o, "Q");  @test o.data.date == Date(2026, 6, 15)
    TW.inject_via_table(o, "a");  @test o.data.date == Date(2026, 6, 1)     # month start
    TW.inject_via_table(o, "e");  @test o.data.date == Date(2026, 6, 30)    # month end
    TW.inject_via_table(o, "A");  @test o.data.date == Date(2026, 1, 1)
    TW.inject_via_table(o, "E");  @test o.data.date == Date(2026, 12, 31)
    o.data.date = Date(2026, 6, 15)
    TW.inject_via_table(o, ".");  @test o.data.date == Dates.today()

    # Multi-key binding: "y" and :pagedown both mean +year.
    o.data.date = Date(2026, 6, 15)
    @test TW.inject_via_table(o, :pagedown) === TW.Handled
    @test o.data.date == Date(2027, 6, 15)
    TW.inject_via_table(o, "Y");  @test o.data.date == Date(2026, 6, 15)

    # Arrow navigation (ncalStyle default true): left/right move by a week.
    @test TW.inject_via_table(o, :left)  === TW.Handled
    @test o.data.date == Date(2026, 6, 8)
    TW.inject_via_table(o, :right)
    @test o.data.date == Date(2026, 6, 15)

    # Accept / Cancel outcomes.
    @test TW.inject_via_table(o, :enter) === TW.Accept
    @test o.value == o.data.date
    @test TW.inject_via_table(o, :esc) === TW.Cancel

    # Unknown key bubbles up.
    @test TW.inject_via_table(o, :f1) === TW.Ignored

    # Help + footer are generated from the table (no help-text constant remains).
    help = TW.helptext_from_bindings(o)
    @test occursin("+day", help) && occursin("select", help) && occursin("holiday cal", help)
    @test occursin("Enter", TW.footer(o))   # :enter renders as "Enter"
end

@testset "FileBrowser adopts FileRow + tree_nav (headless)" begin
    # file_tree_data just walks the filesystem, so we can build a real datalist
    # against a temp tree and exercise the converted rows + shared navigation.
    tmp = mktempdir()
    mkdir(joinpath(tmp, "adir"))
    write(joinpath(tmp, "adir", "a1.txt"), "x")
    write(joinpath(tmp, "adir", "a2.txt"), "y")
    write(joinpath(tmp, "bfile.txt"), "z")

    list = TW.FileRow[]
    osm = Dict{String,Bool}(joinpath(tmp, "adir") => true)   # expand "adir"
    TW.file_tree_data(tmp, list, osm, Any[], Int[], false, :name)

    @test eltype(list) === TW.FileRow
    names = [r.name for r in list]
    @test "adir/" in names && "a1.txt" in names && "a2.txt" in names && "bfile.txt" in names

    iadir = findfirst(==("adir/"), names)
    ia1   = findfirst(==("a1.txt"), names)
    ia2   = findfirst(==("a2.txt"), names)
    ibf   = findfirst(==("bfile.txt"), names)
    @test list[iadir].isdir
    @test TW.depth(list[ia1]) == 2
    @test list[ia1].skiplines isa Vector{Int}

    @test TW.tree_nav(list, ia1, :parent)         == (iadir, true)   # a1 -> adir
    @test TW.tree_nav(list, ia1, :next_sibling)   == (ia2, true)     # a1 -> a2
    @test TW.tree_nav(list, ia2, :next_sibling)   == (ia2, false)    # last child
    @test TW.tree_nav(list, iadir, :next_sibling) == (ibf, true)     # adir -> bfile

    rm(tmp; recursive = true, force = true)
end

@testset "DictTree shares TreeRow + tree_nav (headless)" begin
    # The dict tree reuses tree_data (now producing TreeRow). Build its data
    # object directly and drive the update path that reads row fields
    # (_dt_update_dimensions!) — this is exactly what would crash if the rows
    # were still indexed as tuples.
    data = TW.TwDictTreeData(
        Dict{Any,Bool}(), TW.TreeRow[],
        0, 0, 0, 0,           # datalistlen, tree/type/value widths
        1, 1, 1,              # currentTop, currentLine, currentLeft
        true, "", true, "", "",   # showLineInfo, bottomText, showHelp, helpText, searchText
        false, TW.InlineEditor(String; width = 1),  # isEditing, editor
    )
    o = TW.TwObj(data, Val{:DictTree})
    o.value = Dict("a" => [1, 2], "b" => 3)
    o.title = "root"
    o.data.openstatemap[Any[]] = true
    o.data.openstatemap[Any["a"]] = true

    TW._dt_update_data!(o)    # tree_data + _dt_update_dimensions! (reads x.name/.stack/...)

    @test eltype(o.data.datalist) === TW.TreeRow
    @test o.data.datalistlen > 0
    @test o.data.datatreewidth > 0       # computed from row fields; would error on a tuple
    names = [r.name for r in o.data.datalist]
    @test "root" in names
    @test TW.tree_nav(o.data.datalist, 1, :parent) == (1, false)   # root has no parent
end

@testset "MultiSelect adopts ScrollState (headless)" begin
    o = TW.TwObj(TW.TwMultiSelectData(["a", "b", "c", "d", "e", "f"], String[]), Val{:MultiSelect})
    TW.rebuild_select_datalist(o)        # datalist of [name, checked] pairs
    o.height = 4
    o.borderSizeV = 1                    # viewport = 2
    @test length(o.data.datalist) == 6
    @test o.data.scroll.cursor == 1 && o.data.scroll.top == 1

    TW.move_cursor!(o.data.scroll, 4, length(o.data.datalist), o.height - 2*o.borderSizeV)
    @test o.data.scroll.cursor == 5
    @test o.data.scroll.top == 4         # 5 - 2 + 1

    # resize shrink → clamp_scroll! keeps cursor visible
    o.height = 3                         # viewport now 1
    TW.clamp_scroll!(o)
    @test TW.visible(o.data.scroll, o.data.scroll.cursor, o.height - 2*o.borderSizeV)

    # datalist rows are still [name, checked] pairs (not converted to a struct)
    @test o.data.datalist[1][1] == "a"
    @test o.data.datalist[1][2] == false
end

@testset "Viewer bindings + dual-mode scroll (headless)" begin
    # Navigation mutates only data (vh comes from viewContentDimensions(o)), so
    # inject_via_table can be driven without a window.
    o = TW.TwObj(TW.TwViewerData(), Val{:Viewer})
    TW.setTwViewerMsgs(o, ["line $i" for i in 1:20])
    o.box = true
    o.borderSizeV = 1
    o.borderSizeH = 2
    o.height = 7          # viewContentHeight = 7 - 2 = 5
    o.width = 20

    # --- non-trackLine (default): scrolling moves the top, no cursor ---
    @test o.data.trackLine == false
    @test TW.inject_via_table(o, :down) === TW.Handled
    @test o.data.currentTop == 2
    TW.inject_via_table(o, :pagedown)
    @test o.data.currentTop == 7          # 2 + 5
    TW.inject_via_table(o, :home)
    @test o.data.currentTop == 1 && o.data.currentLeft == 1
    @test TW.inject_via_table(o, Symbol("end")) === TW.Handled
    @test o.data.currentTop == o.data.msglen - o.height + 2   # 20 - 7 + 2 = 15

    # --- trackLine: a cursor moves and stays visible ---
    o.data.trackLine = true
    o.data.currentTop = 1; o.data.currentLine = 1
    TW.inject_via_table(o, :down)
    @test o.data.currentLine == 2 && o.data.currentTop == 1
    TW.inject_via_table(o, :pagedown)         # +5 → line 7, top follows
    @test o.data.currentLine == 7
    @test o.data.currentTop == 3              # 7 - 5 + 1

    # outcomes
    @test TW.inject_via_table(o, :esc) === TW.Cancel
    @test TW.inject_via_table(o, :f10) === TW.Ignored   # unknown key bubbles
    # F11 guarded off when no filename
    @test TW.inject_via_table(o, :F11) === TW.Ignored

    # help generated from the table (defaultViewerHelpText is gone)
    help = TW.helptext_from_bindings(o)
    @test occursin("page up", help) && occursin("halfway toward end", help)
end

@testset "EditTable clamp_scroll! on resize (headless)" begin
    using DataFrames
    df = DataFrame(a = collect(1:30), b = string.(collect(1:30)))
    cols = [
        TW.TwEditTableCol(:a, "A", 6, true, Int, nothing, false),
        TW.TwEditTableCol(:b, "B", 8, true, String, nothing, false),
    ]
    data = TW.TwEditTableData(df, cols, 20, 1, 1, 1, TW.InlineEditor(Int; width = 6), "")
    o = TW.TwObj(data, Val{:EditTable})
    o.borderSizeV = 1
    o.borderSizeH = 1
    o.width = 30
    o.height = 8                 # dataH = 8 - 2 - 1 = 5

    # cursor is row 20 but top is 1 → off-screen; clamp_scroll! must bring it into view
    TW.clamp_scroll!(o)
    @test o.data.currentTop == 20 - 5 + 1     # 16
    @test o.data.currentTop <= o.data.currentRow <= o.data.currentTop + 5 - 1

    # shrink further → top re-clamps to keep the row visible
    o.height = 5                 # dataH = 2
    TW.clamp_scroll!(o)
    @test o.data.currentTop <= o.data.currentRow <= o.data.currentTop + 2 - 1
end

println("\nAll primitives unit tests passed.")
