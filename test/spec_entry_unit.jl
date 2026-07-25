# Headless unit tests for the spec-string entry widget (src/twspecentry.jl).
# The presentation logic (`_spec_hint`, `_spec_detail`, `_spec_valid`,
# `_spec_wordlist`) is pure over the DataFrameAggrSpec parsers, so the
# interesting behaviour is testable without a TTY: valid specs summarise, typos
# surface the parser's did-you-mean, and a `columns` list turns an unknown
# column into a suggestion.
#
# What is NOT tested here: the *content* of the suggestions. `spec_templates` /
# `spec_vocabulary` / `specsummary` live in DataFrameAggrSpec (src/templates.jl)
# because they are grammar knowledge rather than UI, and are covered by that
# package's test/templates.jl -- including the load-bearing "every offered
# template parses and runs on its target column" sweep.
#
# Run:
#   julia --project=. test/spec_entry_unit.jl

using Test
using TermWin
using DataFrames
using Dates

const TW = TermWin

@testset "spec suggestion comes from DataFrameAggrSpec (re-exported)" begin
    # The template catalogue, the completion vocabulary and the structural
    # rendition of a parsed spec live in DataFrameAggrSpec (src/templates.jl) --
    # they are grammar knowledge, not UI -- and are covered by that package's
    # test/templates.jl. TermWin re-exports them so a host with `using TermWin`
    # can reach them; this asserts the re-export and the widget's use of them,
    # not the content.
    df = DataFrame(region = ["E", "W"], sales = [1, 2])
    @test spec_templates(:aggr; coltypes = df, target = :sales) isa Vector{String}
    @test spec_vocabulary(:dim; columns = [:sales]) isa Vector{String}
    @test spec_columns(df) == [:region, :sales]
    @test spec_coltype(df, :sales) === Int
    @test specsummary(parseaggr("sum(_)")) isa String
    @test specfields(parsedim("cumsum(x)")) isa Vector{Pair{String,String}}
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

    # a pivot dim CLASSIFIES groups, so the verb must give one label per
    # group -- a reducer like `mean` is rejected at parse time upstream
    piv = hint("rank(sales) |> groupby(region)")
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
    # both modifiers complete in BOTH kinds: an aggr spec takes a top-level
    # `orderby` (sort the group, then reduce) and a nested `groupby` (the
    # composite reduction), and the `?` templates for :aggr hand out text
    # containing each -- a vocabulary omitting them could not finish a spec
    # this very widget had just suggested
    @test "groupby" in TW._spec_wordlist(:dim, nothing)("gr")
    @test "orderby" in TW._spec_wordlist(:aggr, nothing)("or")
    @test "groupby" in TW._spec_wordlist(:aggr, nothing)("gr")

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
            # columns were derived from coltypes → hint validates them
            @test startswith(e.data.hintfn("sum(sales)"), "✓")
            @test occursin("did you mean 'sales'", e.data.hintfn("sum(salse)"))
        end

        @testset "constructor: target/targetdata narrow the dropdown" begin
            df = DataFrame(region = ["E", "W"], sales = [1, 2])
            e = newTwSpecEntry(rootTwScreen, :aggr; key = :m, coltypes = df,
                               target = :region, targetdata = df.region)
            @test e.data.choices ==
                  spec_templates(:aggr; coltypes = df, target = :region,
                                 targetdata = df.region)
            @test "uniqvalue(_)" in e.data.choices
            @test !("sum(_)" in e.data.choices)      # text target, no numeric reducers
            # the empty-buffer hint spells out what `_` stands for
            @test occursin("_ = region", e.data.hintfn(""))
            # …and F6 repeats it, with the same (narrowed) template list
            d = e.data.detailfn("")
            @test occursin("_  =  region::String", d)
            @test occursin("uniqvalue(_)", d) && !occursin("\n  sum(_)", d)

            # a :dim entry ignores the aggr-only target context
            d2 = newTwSpecEntry(rootTwScreen, :dim; key = :d, coltypes = df,
                                target = :region, targetdata = df.region)
            @test d2.data.choices == spec_templates(:dim; coltypes = df)
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
