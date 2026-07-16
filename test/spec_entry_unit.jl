# Headless unit tests for the spec-string entry widget (src/twspecentry.jl).
# The live-hint logic (`_spec_hint`) and template list are pure functions over the
# DataFrameAggrSpec parsers, so the interesting behaviour is testable without a
# TTY: valid specs summarise, typos surface the parser's did-you-mean, and a
# `columns` list turns an unknown column into a suggestion.
#
# Run:
#   julia --project=. test/spec_entry_unit.jl

using Test
using TermWin
using DataFrames
using Dates

const TW = TermWin

@testset "spec_templates all parse" begin
    for t in spec_templates(:aggr)
        @test parseaggr(t) isa TW.SafeAggrSpec
    end
    for t in spec_templates(:dim)
        @test parsedim(t) isa TW.SafeDimSpec
    end
    @test_throws ErrorException spec_templates(:bogus)
end

@testset "type-sensitive aggr templates" begin
    df = DataFrame(region = ["E", "W"], sales = [1, 2], score = [10.0, 20.0])
    t = spec_templates(:aggr; coltypes = df)

    # numeric columns → numeric reducers; text columns → uniq/strjoinuniq
    @test "sum(sales)"        in t
    @test "median(sales)"     in t
    @test "std(score)"        in t
    @test "uniqvalue(region)" in t
    @test "strjoinuniq(region)" in t
    # a numeric reducer is NOT offered for a text column (and vice versa)
    @test !("sum(region)"        in t)
    @test !("strjoinuniq(sales)" in t)

    # the concrete suggestions parse and validate against the frame
    for s in t
        occursin('_', s) && continue          # skip the generic `_` tail
        @test parseaggr(s; columns = propertynames(df)) isa TW.SafeAggrSpec
    end

    # nullable numeric still reads as numeric (nonmissingtype peels the Union)
    dfm = DataFrame(x = Union{Missing,Int}[1, missing])
    @test "sum(x)" in spec_templates(:aggr; coltypes = dfm)
end

@testset "type-sensitive dim templates" begin
    df = DataFrame(region = ["E", "W"],
                   date   = [Date(2026, 1, 1), Date(2026, 2, 1)],
                   sales  = [1, 2])
    t = spec_templates(:dim; coltypes = df)

    @test "discretize(sales, [0, 20, 40, 60, 80, 100])" in t
    @test "quantiles(sales, 4)"          in t
    @test "cumsum(sales) |> orderby(date)" in t   # ordered by the date column
    @test "topnames(region, sales, 5)"   in t     # text col + numeric measure

    for s in t
        @test parsedim(s) isa TW.SafeDimSpec
    end
end

@testset "coltypes accepts dict + pairs, order preserved" begin
    d = TW._normalize_coltypes(Dict(:a => Int, :b => String))
    @test Set(d) == Set([:a => Int, :b => String])
    p = TW._normalize_coltypes([:x => Float64, :y => Symbol])
    @test p == [:x => Float64, :y => Symbol]      # iteration order kept
    @test TW._normalize_coltypes(nothing) === nothing
end

@testset "aggr hint" begin
    hint(s) = TW._spec_hint(:aggr, nothing, s)

    # empty → prompt nudging toward the `?` dropdown
    @test occursin("templates", hint(""))

    # valid → ✓ summary naming the reducer
    v = hint("sum(_ * wt) / sum(wt)")
    @test startswith(v, "✓")
    @test occursin("wt", v)

    # unknown op → ✗ with the parser's did-you-mean repair, prefix stripped
    e = hint("maen(_)")
    @test startswith(e, "✗")
    @test occursin("did you mean 'mean'", e)
    @test !occursin("parseaggr:", e)      # prefix stripped for width
end

@testset "dim hint + kind inference" begin
    hint(s) = TW._spec_hint(:dim, nothing, s)

    win = hint("cumsum(sales) |> orderby(date)")
    @test startswith(win, "✓")
    @test occursin("ordered by date", win)

    piv = hint("mean(sales) |> groupby(region)")
    @test occursin("pivot by region", piv)

    # a bare column is a chain key, not a dim spec — parser says so
    @test startswith(hint("region"), "✗")
end

@testset "column validation via `columns`" begin
    cols = [:region, :sales, :date]
    ok  = TW._spec_hint(:dim, cols, "cumsum(sales) |> orderby(date)")
    @test startswith(ok, "✓")

    # a misspelled column becomes a did-you-mean against the known columns
    bad = TW._spec_hint(:dim, cols, "cumsum(salse) |> orderby(date)")
    @test startswith(bad, "✗")
    @test occursin("did you mean 'sales'", bad)
end

@testset "registered under the @twlayout short name" begin
    @test :specentry in twlayout_widgets()
end

@testset "commit validator (_spec_valid)" begin
    cols = [:region, :sales, :date]
    @test TW._spec_valid(:aggr, cols, "")                    # empty allowed
    @test TW._spec_valid(:aggr, cols, "sum(sales)")
    @test !TW._spec_valid(:aggr, cols, "maen(sales)")        # unknown op
    @test !TW._spec_valid(:aggr, cols, "sum(salse)")         # unknown column
    @test TW._spec_valid(:dim, cols, "cumsum(sales) |> orderby(date)")
    @test !TW._spec_valid(:dim, cols, "region")              # bare key, not a dim
end

@testset "identifier completion vocabulary (_spec_wordlist)" begin
    wl = TW._spec_wordlist(:aggr, [:sales, :score, :region])
    @test "sales"  in wl("sa")
    @test "score"  in wl("sc")
    @test "mean"   in wl("me")       # operator from listops()
    @test "median" in wl("me")
    @test isempty(wl("zzz"))
    # dim adds the two modifiers; aggr does not
    @test "groupby" in TW._spec_wordlist(:dim, nothing)("gr")
    @test !("orderby" in TW._spec_wordlist(:aggr, nothing)("or"))

    # editor-level completion mechanics: single candidate fills in
    ed = TW.InlineEditor(String; width = 40)
    TW.editor_insert!(ed, "sum(sal")
    w = TW.editor_word_before_cursor(ed)
    @test w[1] == "sal"
    cands = TW._spec_wordlist(:aggr, [:sales])("sal")
    TW.editor_replace_range!(ed, w[2], w[3], only(cands))
    @test ed.buffer == "sum(sales"

    @test TW.longest_common_prefix(["mean", "median"]) == "me"
    @test TW.longest_common_prefix(["sales"]) == "sales"
end

@testset "F6 detail text (_spec_detail)" begin
    cols = [:region, :sales, :date]
    d_ok = TW._spec_detail(:dim, cols, "cumsum(sales) |> orderby(date)")
    @test occursin("✓ parses", d_ok)
    @test occursin("window kind", d_ok)
    @test occursin("Available columns", d_ok)

    d_bad = TW._spec_detail(:aggr, cols, "maen(sales)")
    @test occursin("✗", d_bad)
    @test occursin("did you mean 'mean'", d_bad)  # full, untruncated message

    d_empty = TW._spec_detail(:aggr, cols, "")
    @test occursin("Templates:", d_empty)
end

@testset "LaTeX-style Tab completion (editor_latex_complete!)" begin
    # canonical Julia symbols relevant to the spec grammar
    tbl = TW.latex_symbol_table()
    @test tbl["\\circ"] == "∘"
    @test tbl["\\ne"]   == "≠"
    @test tbl["\\le"]   == "≤"
    @test tbl["\\ge"]   == "≥"

    complete(s, cur = length(s) + 1) = begin
        ed = TW.InlineEditor(String; width = 40)
        TW.editor_insert!(ed, s)
        ed.cursorPos = cur
        ok = TW.editor_latex_complete!(ed)
        (ok, ed.buffer, ed.cursorPos)
    end

    # at end of buffer
    ok, buf, cur = complete("cumsum(x) \\circ")
    @test ok && buf == "cumsum(x) ∘" && cur == length(collect(buf)) + 1

    @test complete("a \\ne")[2] == "a ≠"
    @test complete("x \\le")[2] == "x ≤"

    # mid-buffer: cursor right after "\\ne", text after it preserved
    ok, buf, cur = complete("a \\ne b", 6)
    @test ok && buf == "a ≠ b" && cur == 4     # cursor lands after the inserted ≠

    # nothing to complete → false, buffer untouched (so Tab can move focus)
    @test complete("sum(sales)")[1] == false
    @test complete("")[1] == false
    @test complete("\\notasymbol")[1] == false   # unknown name is left as typed
end

# The constructor links a real plane, so it needs a Notcurses session; skip the
# set (like the other headless widget tests) if one can't come up here.
session_ok = false
try
    TW.initsession()
    global session_ok = true
catch err
    @warn "spec_entry_unit.jl: no Notcurses session available, skipping ctor set" err
end

if session_ok
    try
        @testset "constructor wires hint + choices" begin
            e = newTwSpecEntry(rootTwScreen, :aggr;
                key = :measure, columns = [:sales, :wt])
            @test e.formkey === :measure
            @test e.data.hintfn !== nothing
            @test e.data.choices == spec_templates(:aggr)
            # the wired hintfn runs the real parser end-to-end
            @test startswith(e.data.hintfn("sum(sales)"), "✓")
            @test_throws ErrorException newTwSpecEntry(rootTwScreen, :bogus)
        end

        @testset "constructor: coltypes drives choices + validation" begin
            df = DataFrame(region = ["E"], sales = [1])
            e = newTwSpecEntry(rootTwScreen, :aggr; key = :m, coltypes = df)
            # type-sensitive dropdown
            @test "sum(sales)" in e.data.choices
            @test "uniqvalue(region)" in e.data.choices
            # columns were derived from coltypes → hint validates them
            @test startswith(e.data.hintfn("sum(sales)"), "✓")
            @test occursin("did you mean 'sales'", e.data.hintfn("sum(salse)"))
        end

        @testset "Tab completion is on by default and routes through inject" begin
            e = newTwSpecEntry(rootTwScreen, :dim; key = :d)
            @test getfield(e.data, :latex_complete) == true
            # type a completable sequence, then Tab → expands (Handled, consumed)
            TW.editor_insert!(e.data.editor, "cumsum(x) \\circ")
            @test TW.inject(e, :tab) == TW.Handled
            @test e.data.editor.buffer == "cumsum(x) ∘"
            # with nothing to complete, Tab is yielded so the form can move focus
            @test TW.inject(e, :tab) == TW.Ignored
        end

        @testset "wires validator / word_complete / detailfn; commit is gated" begin
            df = DataFrame(region = ["E"], sales = [1])
            e = newTwSpecEntry(rootTwScreen, :aggr; key = :m, coltypes = df)
            @test getfield(e.data, :validator)     !== nothing
            @test getfield(e.data, :word_complete) !== nothing
            @test getfield(e.data, :detailfn)      !== nothing

            # a valid spec commits (Enter → Accept, value set)
            TW.editor_set_buffer!(e.data.editor, "sum(sales)")
            @test TW.inject(e, :enter) == TW.Accept
            @test e.value == "sum(sales)"

            # an invalid spec is refused: Enter stays (Handled), value unchanged
            TW.editor_set_buffer!(e.data.editor, "maen(sales)")
            @test TW.inject(e, :enter) == TW.Handled
            @test e.value == "sum(sales)"          # last valid value preserved

            # identifier completion through inject: "sum(sal" + Tab → "sum(sales"
            TW.editor_set_buffer!(e.data.editor, "sum(sal")
            @test TW.inject(e, :tab) == TW.Handled
            @test e.data.editor.buffer == "sum(sales"
        end
    finally
        TW.endsession()
    end
end

println("spec_entry_unit.jl: all tests passed.")
