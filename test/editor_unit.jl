# Headless unit tests for the unified InlineEditor (src/editor.jl).
# The editor is window-free, so its entire behaviour is testable without a TTY.
#
# Run:
#   julia --project=. test/editor_unit.jl

using Test
using TermWin
using Dates

const TW = TermWin

@testset "InlineEditor constructor / conversion defaults" begin
    @test TW.InlineEditor(String).conversion == "s"
    @test TW.InlineEditor(Int).conversion == "d"
    @test TW.InlineEditor(Float64).conversion == "f"
    @test TW.InlineEditor(UInt).conversion == "x"
    e = TW.InlineEditor(Int; width = 12, missingok = true)
    @test e.width == 12 && e.missingok && e.valuetype === Int
end

@testset "editor_load! / value_to_buf per type" begin
    e = TW.InlineEditor(Int; width = 10)
    TW.editor_load!(e, 1234)
    @test e.buffer == "1,234" && e.cursorPos == length(e.buffer) + 1 && !e.dirty

    es = TW.InlineEditor(String; width = 10)
    TW.editor_load!(es, "hi")
    @test es.buffer == "hi"

    ed = TW.InlineEditor(Date; width = 12)
    TW.editor_load!(ed, Date(2026, 6, 4))
    @test ed.buffer == "2026-06-04"

    eb = TW.InlineEditor(Bool; width = 6)
    TW.editor_load!(eb, true)
    @test eb.buffer == "true"           # NOT "1"

    em = TW.InlineEditor(Int; width = 6)
    TW.editor_load!(em, missing)
    @test em.buffer == ""
end

@testset "editor_commit parity with evalNFormat(TwEntryData)" begin
    # The parse engine moved to editor.jl; assert the InlineEditor path matches
    # the legacy TwEntryData path byte-for-byte across a battery of inputs.
    cases = [
        (Int,     "1,234"),
        (Int,     "-57"),
        (Int,     "x"),          # invalid
        (Float64, "1,234.5"),
        (Float64, "3.0e6"),
        (Float64, ""),           # invalid (→ nothing)
        (Date,    "1jan2024"),
        (Date,    "2024-02-29"),
        (Date,    "garbage"),
        (String,  "anything"),
        (Bool,    "true"),
        (Bool,    "maybe"),
        (Rational{Int}, "3.5"),
    ]
    for (T, s) in cases
        d  = TW.TwEntryData(T)
        ie = TW.InlineEditor(T; width = 14)
        @test TW.evalNFormat(ie, s, 14) == TW.evalNFormat(d, s, 14)
    end
end

@testset "editor_commit + missingok" begin
    e = TW.InlineEditor(Int; width = 8)
    TW.editor_load!(e, 42)
    @test TW.editor_commit(e) == (42, true)

    e.buffer = "nope"
    (v, ok) = TW.editor_commit(e)
    @test v === nothing && ok == false && e.incomplete

    em = TW.InlineEditor(Int; width = 8, missingok = true)
    em.buffer = ""
    @test isequal(TW.editor_commit(em), (missing, true))
end

@testset "editor_handle: navigation + structural edits" begin
    e = TW.InlineEditor(String; width = 20)
    TW.editor_load!(e, "abc")            # cursor at 4 (end)
    @test TW.editor_handle(e, :left) === :handled && e.cursorPos == 3
    @test TW.editor_handle(e, :home) === :handled && e.cursorPos == 1
    @test TW.editor_handle(e, :home) === :rejected          # already home
    @test TW.editor_handle(e, :left) === :at_left_edge      # host decides
    @test TW.editor_handle(e, Symbol("end")) === :handled && e.cursorPos == 4
    @test TW.editor_handle(e, :right) === :at_right_edge

    # backspace / delete
    TW.editor_load!(e, "abc"); e.cursorPos = 4
    @test TW.editor_handle(e, :backspace) === :handled && e.buffer == "ab"
    e.cursorPos = 1
    @test TW.editor_handle(e, :delete) === :handled && e.buffer == "b"
    @test TW.editor_handle(e, :backspace) === :rejected     # nothing before cursor

    # overwrite toggle
    @test TW.editor_handle(e, :ctrl_r) === :handled && e.overwriteMode
    # clear
    @test TW.editor_handle(e, :ctrl_k) === :handled && e.buffer == ""
end

@testset "editor_handle: type-specific insert rules" begin
    # String: any char inserts
    es = TW.InlineEditor(String; width = 20); TW.editor_load!(es, "")
    @test TW.editor_handle(es, "z") === :handled && es.buffer == "z"

    clearbuf!(e) = (e.buffer = ""; e.cursorPos = 1; e.fieldLeftPos = 1; e)

    # Int: digits ok; '.', 'e', letters rejected; '-' only at start
    ei = TW.InlineEditor(Int; width = 20); clearbuf!(ei)
    @test TW.editor_handle(ei, "5") === :handled && ei.buffer == "5"
    @test TW.editor_handle(ei, ".") === :rejected
    @test TW.editor_handle(ei, "a") === :rejected
    @test TW.editor_handle(ei, "-") === :rejected            # not at start (after "5")
    clearbuf!(ei); @test TW.editor_handle(ei, "-") === :handled  # at start

    # Float: '.', 'e', sign rules
    ef = TW.InlineEditor(Float64; width = 20); clearbuf!(ef)
    @test TW.editor_handle(ef, "1") === :handled
    @test TW.editor_handle(ef, ".") === :handled && ef.buffer == "1."
    @test TW.editor_handle(ef, ".") === :handled            # jump to existing point, no dup
    @test count(==('.'), ef.buffer) == 1
    @test TW.editor_handle(ef, "e") === :handled
    @test TW.editor_handle(ef, "e") === :rejected           # only one 'e'

    # Bool: t/f only
    eb = TW.InlineEditor(Bool; width = 6); TW.editor_load!(eb, false)
    @test TW.editor_handle(eb, "t") === :handled && eb.buffer == "true"
    @test TW.editor_handle(eb, "x") === :rejected
end

@testset "editor_handle: picker signals" begin
    # Date '?' → calendar; ',' formats
    ed = TW.InlineEditor(Date; width = 12); TW.editor_load!(ed, Date(2026,1,1))
    @test TW.editor_handle(ed, "?") === :open_calendar
    ed.buffer = "1jan2024"
    @test TW.editor_handle(ed, ",") === :handled        # reformats to detected family
    @test TW.editor_commit(ed)[1] == Date(2024, 1, 1)

    # Enum cells signal :open_enum and never text-edit
    ee = TW.InlineEditor(String; width = 10, enumvalues = ["a", "b", "c"])
    TW.editor_load!(ee, "a")
    @test TW.editor_handle(ee, "x") === :open_enum
    @test TW.editor_handle(ee, :enter) === :open_enum
    @test TW.editor_handle(ee, :left) === :at_left_edge
    @test TW.editor_handle(ee, :ctrl_k) === :ignored        # missingok=false
    ee2 = TW.InlineEditor(String; width = 10, enumvalues = ["a"], missingok = true)
    TW.editor_load!(ee2, "a")
    @test TW.editor_handle(ee2, :ctrl_k) === :handled && ee2.buffer == ""

    # unknown keys bubble to the host
    @test TW.editor_handle(TW.InlineEditor(Int), :f10) === :ignored
end

@testset "editor_set_buffer! (picker round-trip)" begin
    ed = TW.InlineEditor(Date; width = 12); TW.editor_load!(ed, Date(2020,1,1))
    TW.editor_set_buffer!(ed, "2026-12-31")
    @test ed.buffer == "2026-12-31" && ed.cursorPos == length(ed.buffer) + 1 && ed.dirty
end

@testset "editor_render: 3 branches" begin
    # number: right-justified into the field
    ei = TW.InlineEditor(Int; width = 8); TW.editor_load!(ei, 123)
    (outstr, rcurs, lm, rm) = TW.editor_render(ei)
    @test length(outstr) == 8 && outstr == "    123 " && !lm && !rm

    # date: left-justified, padded
    ed = TW.InlineEditor(Date; width = 12); TW.editor_load!(ed, Date(2026,6,4))
    (outstr, _, lm, rm) = TW.editor_render(ed)
    @test outstr == "2026-06-04  " && !lm && !rm

    # string overflow: clipped to width, right-overflow flagged
    es = TW.InlineEditor(String; width = 5); TW.editor_load!(es, "hello world")
    (outstr, _, lm, rm) = TW.editor_render(es)
    @test textwidth(outstr) == 5 && !lm && rm
end

@testset "editor_tick!" begin
    ei = TW.InlineEditor(Int; width = 10, tickSize = 5); TW.editor_load!(ei, 10)
    @test TW.editor_tick!(ei, 1) && TW.editor_commit(ei)[1] == 15
    @test TW.editor_tick!(ei, -1) && TW.editor_commit(ei)[1] == 10

    ed = TW.InlineEditor(Date; width = 12); TW.editor_load!(ed, Date(2026,6,4))
    @test TW.editor_tick!(ed, 1) && TW.editor_commit(ed)[1] == Date(2026,6,5)

    # no tick configured for a number → no-op
    e0 = TW.InlineEditor(Int; width = 10, tickSize = 0); TW.editor_load!(e0, 7)
    @test TW.editor_tick!(e0, 1) == false
end

@testset "twentry hosts InlineEditor (headless)" begin
    # apply_default! doesn't touch the window, so the host wiring is testable.
    d = TW.TwEntryData(Int)
    o = TW.TwObj(d, Val{:Entry})
    o.width = 12; o.box = true; o.borderSizeH = 1; o.title = ""
    TW.apply_default!(o, 1234)
    @test o.value == 1234
    @test o.data.inputText == "1,234"            # public name → editor.buffer
    @test o.data.editor.buffer == "1,234"
    @test o.data.valueType === Int               # public name → editor.valuetype

    # public field forwarding round-trips (the searchbox/helper-entry contract)
    o.data.cursorPos = 2;  @test o.data.editor.cursorPos == 2
    o.data.inputText = "x"; @test o.data.editor.buffer == "x"
    o.data.tickSize = 3;   @test o.data.editor.tickSize == 3

    # the TwEntryData parse shim matches the InlineEditor path
    @test TW.evalNFormat(o.data, "9,999", 10) == TW.evalNFormat(o.data.editor, "9,999", 10)
end

@testset "twedittable hosts InlineEditor (headless)" begin
    using DataFrames
    df = DataFrame(n = [10, 20], s = ["a", "b"])
    cols = [
        TW.TwEditTableCol(:n, "N", 6, true, Int, nothing, false),
        TW.TwEditTableCol(:s, "S", 6, true, String, nothing, false),
    ]
    # _et_load_cell! / editor_handle / _et_commit_cell! are all window-free.
    data = TW.TwEditTableData(df, cols, 1, 1, 1, 1, TW.InlineEditor(String; width = 1), "")
    TW._et_load_cell!(data)
    @test data.editor.valuetype === Int && data.editor.buffer == "10"

    TW.editor_handle(data.editor, "5")        # cursor at end → "105"
    @test data.editor.buffer == "105"
    @test TW._et_commit_cell!(data)
    @test data.df[1, :n] == 105

    data.currentCol = 2                        # string column
    TW._et_load_cell!(data)
    @test data.editor.buffer == "a"
    TW.editor_handle(data.editor, "x")
    @test TW._et_commit_cell!(data)
    @test data.df[1, :s] == "ax"

    # enum + missingok: empty buffer commits to missing
    ecols = [TW.TwEditTableCol(:n, "N", 6, true, String, ["x", "y"], true)]
    edf = DataFrame(n = Union{String,Missing}["x"])
    edata = TW.TwEditTableData(edf, ecols, 1, 1, 1, 1, TW.InlineEditor(String; width = 1), "")
    TW._et_load_cell!(edata)
    @test TW.editor_handle(edata.editor, :ctrl_k) === :handled   # clear (missingok)
    @test TW._et_commit_cell!(edata)
    @test edata.df[1, :n] === missing
end

@testset "twdicttree hosts InlineEditor (headless)" begin
    # _dt_begin_edit! / editor_handle / _dt_commit_edit! are window-free.
    data = TW.TwDictTreeData(
        Dict{Any,Bool}(), TW.TreeRow[], 0, 0, 0, 0, 1, 1, 1,
        true, "", true, "",
        false, TW.InlineEditor(String; width = 1),
    )
    o = TW.TwObj(data, Val{:DictTree})
    o.value = Dict{Any,Any}("a" => 10, "b" => "hi")
    o.title = "root"
    o.height = 20; o.width = 60; o.borderSizeV = 1; o.borderSizeH = 2
    o.data.openstatemap[Any[]] = true
    TW._dt_update_data!(o)

    # edit the Int leaf "a"
    ia = findfirst(r -> r.stack == Any["a"], o.data.datalist)
    o.data.currentLine = ia
    @test TW._dt_begin_edit!(o)
    @test o.data.isEditing
    @test o.data.editor.valuetype === Int
    @test o.data.editor.buffer == "10"               # plain string(val) seeding
    TW.editor_handle(o.data.editor, "5")             # cursor at end → "105"
    @test o.data.editor.buffer == "105"
    @test TW._dt_commit_edit!(o)
    @test o.value["a"] == 105
    @test !o.data.isEditing

    # edit the String leaf "b" (datalist was rebuilt by the commit)
    ib = findfirst(r -> r.stack == Any["b"], o.data.datalist)
    o.data.currentLine = ib
    @test TW._dt_begin_edit!(o)
    @test o.data.editor.buffer == "hi"
    TW.editor_handle(o.data.editor, "!")
    @test TW._dt_commit_edit!(o)
    @test o.value["b"] == "hi!"
end

println("\nAll InlineEditor unit tests passed.")
