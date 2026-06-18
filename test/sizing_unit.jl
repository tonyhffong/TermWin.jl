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
