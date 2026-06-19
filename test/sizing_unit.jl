# Headless unit tests for the flexible layout sizing hints (:content/:fill/Flex).
# The arithmetic lives in window-free helpers in src/sizing.jl, so the whole
# distribution model is exercised without a TTY.
#
# Run:
#   julia --project=. test/sizing_unit.jl

using Test
using TermWin

const TW = TermWin

# A widget data type with no natural_* override, for the generic-fallback test.
struct _NoNatData end

# ── headless builders for the recursive resolve_flex! tests ───────────────────
# resolve_flex! takes an explicit `budget` kwarg, so the whole top-down solve can
# be driven without a TTY (no NC.Plane needed).
function _mkleaf(; dh, dw, h = 1, w = 1)
    o = TW.TwObj(_NoNatData(), Val{:Leaf})
    o.height = h; o.width = w
    o.desiredHeight = dh; o.desiredWidth = dw
    o.box = false; o.borderSizeV = 0; o.borderSizeH = 0
    o
end
function _mklist(horizontal; dh, dw, h = 1, w = 1)
    o = TW.TwObj(TW.TwListData(), Val{:List})
    o.data.horizontal = horizontal
    o.height = h; o.width = w
    o.desiredHeight = dh; o.desiredWidth = dw
    o.data.canvasheight = h; o.data.canvaswidth = w
    o.box = false; o.borderSizeV = 0; o.borderSizeH = 0
    o
end
function _attach!(parent, kids...)
    for k in kids
        k.window = TW.TwWindow(WeakRef(parent), 0, 0, k.height, k.width)
        push!(parent.data.widgets, k)
    end
    parent
end

@testset "spec predicates" begin
    @test TW.is_flex(:fill)
    @test TW.is_flex(TW.Flex(2))
    @test !TW.is_flex(:content)
    @test !TW.is_flex(0.5)

    @test TW.is_content(:content)
    @test TW.is_content(:auto)
    @test !TW.is_content(:fill)
    @test !TW.is_content(5)

    @test TW.flex_weight(TW.Flex(2.5)) == 2.5
    @test TW.flex_weight(:fill) == 1.0
    @test TW.Flex().weight == 1.0
end

@testset "cross_fill_factor" begin
    @test TW.cross_fill_factor(0.5) == 0.5
    @test TW.cross_fill_factor(1.0) == 1.0
    @test TW.cross_fill_factor(:fill) == 1.0
    @test TW.cross_fill_factor(TW.Flex(3)) == 1.0
    @test TW.cross_fill_factor(5) === nothing        # Int is fixed, not fill
    @test TW.cross_fill_factor(:content) === nothing
    @test TW.cross_fill_factor(1.5) === nothing      # out of (0,1]
end

@testset "resolve_dim — literals" begin
    @test TW.resolve_dim(5, 20, 0; main = true) == 5
    @test TW.resolve_dim(100, 20, 0; main = true) == 20      # clamped to parent
    @test TW.resolve_dim(0.5, 20, 0; main = false) == 10
    # The codebase signals illegal sizes by throwing a raw String (matching alignxy!).
    @test_throws String TW.resolve_dim(1.5, 20, 0; main = true)
    @test_throws String TW.resolve_dim(:bogus, 20, 0; main = true)
end

@testset "resolve_dim — hints" begin
    # :content → natural, clamped to parent
    @test TW.resolve_dim(:content, 20, 8; main = true) == 8
    @test TW.resolve_dim(:content, 20, 30; main = true) == 20
    @test TW.resolve_dim(:auto, 20, 5; main = true) == 5
    # :fill / Flex: provisional 1 on the main axis, span on the cross axis
    @test TW.resolve_dim(:fill, 20, 9; main = true) == 1
    @test TW.resolve_dim(:fill, 20, 9; main = false) == 20
    @test TW.resolve_dim(TW.Flex(2), 20, 9; main = true) == 1
    @test TW.resolve_dim(TW.Flex(2), 20, 9; main = false) == 20
end

@testset "allocate_main — fixed + fill" begin
    # label(3) + fill: fill takes the leftover of a 20-row budget
    specs    = [3, :fill]
    presizes = [3, 1]
    naturals = [3, 6]
    out = TW.allocate_main(specs, presizes, naturals, 20)
    @test out == [3, 17]
    @test sum(out) == 20
end

@testset "allocate_main — content sizes to natural and caps at budget" begin
    @test TW.allocate_main([:content], [1], [8], 20) == [8]
    @test TW.allocate_main([:content], [1], [30], 20) == [20]   # capped
    # label + content table + fill tree
    specs    = [1, :content, :fill]
    presizes = [1, 1, 1]
    naturals = [1, 6, 50]
    out = TW.allocate_main(specs, presizes, naturals, 20)
    @test out == [1, 6, 13]                                     # fill = 20 - 1 - 6
    @test sum(out) == 20
end

@testset "allocate_main — weighted split 2:1" begin
    specs    = [6, TW.Flex(2), TW.Flex(1)]
    presizes = [6, 1, 1]
    naturals = [6, 1, 1]
    out = TW.allocate_main(specs, presizes, naturals, 30)       # remaining = 24
    @test out == [6, 16, 8]
    @test sum(out) == 30
end

@testset "allocate_main — rounding remainder absorbed by last flex" begin
    specs    = [1, :fill, :fill]
    presizes = [1, 1, 1]
    naturals = [1, 1, 1]
    out = TW.allocate_main(specs, presizes, naturals, 10)       # remaining = 9
    @test out == [1, 4, 5]                                      # last absorbs the odd row
    @test sum(out) == 10
end

@testset "allocate_main — unbounded list falls back to natural" begin
    # budget <= 0 means a nested shrink-wrap list: fill/content both → natural
    specs    = [:fill, :content, 4]
    presizes = [1, 1, 4]
    naturals = [7, 9, 4]
    out = TW.allocate_main(specs, presizes, naturals, 0)
    @test out == [7, 9, 4]
end

@testset "natural_* overrides compute from content (headless)" begin
    # Tree override: datalist-driven height/width, no TTY needed.
    o = TW.TwObj(TW.TwTreeData(), Val{:Tree})
    o.borderSizeV = 1
    o.borderSizeH = 2
    o.data.openstatemap[Any[]] = true
    TW.tree_data(Dict("a" => 1, "b" => 2), "root",
        o.data.datalist, o.data.openstatemap, Any[], Int[], true)
    @test !isempty(o.data.datalist)
    @test TW.natural_height(o) == length(o.data.datalist) + 2 * o.borderSizeV
    @test TW.natural_width(o) > 0

    # Viewer override: message-count-driven height.
    v = TW.TwObj(TW.TwViewerData(), Val{:Viewer})
    v.box = true
    v.borderSizeV = 1
    v.borderSizeH = 2
    TW.setTwViewerMsgs(v, ["line one", "line two", "line three"])
    @test TW.natural_height(v) == v.data.msglen + 2 * v.borderSizeV
    @test TW.natural_width(v) >= 25

    # Generic fallback: a widget whose data type has no override returns its
    # current allocated size. (Dispatch is on the data type, so this needs a
    # type with no natural_* method — a viewer would still hit the override.)
    g = TW.TwObj(_NoNatData(), Val{:NoNat})
    g.height = 7
    g.width = 13
    @test TW.natural_height(g) == 7
    @test TW.natural_width(g) == 13
end

@testset "allocate_main — no leftover space" begin
    # fixed children already fill the budget; fill child floors at 1
    specs    = [15, :fill]
    presizes = [15, 1]
    naturals = [15, 5]
    out = TW.allocate_main(specs, presizes, naturals, 12)       # used 15 > budget
    @test out[1] == 15
    @test out[2] == 1                                           # floor, even with no room
end

@testset "resolve_flex! recursion — same-axis nested vstack" begin
    # root vstack (budget 20, canvas width 40):
    #   leaf A: fixed height 3
    #   nested vstack B: height=:fill  → gets 20-3 = 17, then splits 17 to its
    #                    two :fill leaves (8 / 9)
    root = _mklist(false; dh = 1.0, dw = 1.0)
    root.data.canvasheight = 20
    root.data.canvaswidth  = 40
    a = _mkleaf(; dh = 3, dw = 1.0, h = 3)
    b = _mklist(false; dh = :fill, dw = 1.0)
    b1 = _mkleaf(; dh = :fill, dw = 1.0)
    b2 = _mkleaf(; dh = :fill, dw = 1.0)
    _attach!(b, b1, b2)
    _attach!(root, a, b)

    TW.resolve_flex!(root; budget = 20)

    @test a.height == 3
    @test b.height == 17                 # :fill share of the root
    @test b.width  == 40                 # pinned to the parent's cross extent
    @test (b1.height, b2.height) == (8, 9)   # 17 split, last absorbs remainder
    @test b1.width == 40 && b2.width == 40    # leaf cross-fill to B's width
    @test b.ypos == 3                    # stacked below A
end

@testset "resolve_flex! recursion — perpendicular (columns fill row height)" begin
    # root hstack (width budget 30, height 10):
    #   col1 vstack width=Flex(2) → 20 wide, pinned to 10 tall
    #   col2 vstack width=Flex(1) → 10 wide, pinned to 10 tall
    #   each column's lone :fill leaf fills the column's full height (10)
    root = _mklist(true; dh = 1.0, dw = 1.0)
    root.data.canvasheight = 10
    root.data.canvaswidth  = 30
    col1 = _mklist(false; dh = 1.0, dw = TW.Flex(2))
    col2 = _mklist(false; dh = 1.0, dw = TW.Flex(1))
    l1 = _mkleaf(; dh = :fill, dw = 1.0)
    l2 = _mkleaf(; dh = :fill, dw = 1.0)
    _attach!(col1, l1)
    _attach!(col2, l2)
    _attach!(root, col1, col2)

    TW.resolve_flex!(root; budget = 30)

    @test (col1.width, col2.width) == (20, 10)   # 2:1 width split
    @test col1.height == 10 && col2.height == 10 # cross-pinned to row height
    @test l1.height == 10 && l2.height == 10     # :fill leaf fills column height
    @test l1.width == 20 && l2.width == 10       # leaf cross-fill to column width
    @test col2.xpos == 20                        # placed after col1
end

@testset "resolve_flex! — numeric/default nested list stays shrink-wrapped" begin
    # B has the default size (1.0): it must NOT participate or be recursed, so its
    # own :fill leaf is left untouched (today's behavior — no regression).
    root = _mklist(false; dh = 1.0, dw = 1.0)
    root.data.canvasheight = 20
    root.data.canvaswidth  = 40
    b = _mklist(false; dh = 1.0, dw = 1.0, h = 5, w = 12)
    inner = _mkleaf(; dh = :fill, dw = 1.0, h = 1, w = 12)
    _attach!(b, inner)
    _attach!(root, b)

    TW.resolve_flex!(root; budget = 20)

    @test b.height == 5      # kept its shrink-wrapped height (treated as fixed)
    @test b.width  == 12     # NOT pinned to the parent's cross extent
    @test inner.height == 1  # NOT distributed — B never recursed into
end
