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
    @test occursin("shape", d_ok) && occursin("one value per row", d_ok)  # opshape gloss

    d_bad = TW._spec_detail(:aggr, cols, "maen(sales)")
    @test occursin("✗", d_bad)
    # F6 is where the message is repaid in full: the panel trims the host-facing
    # aside and the [in aggr"…"] tag, this must not
    @test occursin("did you mean 'mean'", d_bad)
    @test occursin("listops()", d_bad)
    @test occursin("[in aggr\"maen(sales)\"]", d_bad)
    # …plus the structured channel
    @test occursin("code  : unknown_op", d_bad)
    @test occursin("token : maen", d_bad)
    @test occursin("fix   : mean", d_bad)

    d_empty = TW._spec_detail(:aggr, cols, "")
    @test occursin("Templates:", d_empty)
end

@testset "SpecDiag: the structured channel drives behaviour" begin
    cols = [:region, :sales, :date]
    an(s) = TW._spec_analyze(:aggr, cols, s, nothing)

    ok = an("sum(sales)")
    @test ok.ok && ok.span === nothing && ok.fix === nothing
    @test occursin("reduce via sum", ok.text)

    e = an("maen(sales)")
    @test !e.ok && e.code === :unknown_op
    @test e.fix == "mean"
    @test e.span == 1:4                       # characters, into the buffer
    @test occursin("did you mean 'mean'", e.text)

    # a column typo comes from checkcols, which tags its spec differently — the
    # code normalises that away for us
    c = an("sum(salse)")
    @test c.code === :unknown_column && c.fix == "sales" && c.span == 5:9

    # the colon flip: the fix replaces the QUOTING too, so the span covers it
    q = an("sum(:sales)")
    @test q.code === :symbol_literal && q.span == 5:10   # ":sales", colon included

    @test an("").empty
    @test an("sum(").incomplete
end

@testset "span → character range survives whitespace and multibyte text" begin
    cols = [:région, :sales]
    # leading whitespace: the parser sees the STRIPPED source, the editor does not
    d = TW._spec_analyze(:aggr, cols, "   maen(sales)", nothing)
    @test d.span == 4:7
    @test "   maen(sales)"[d.span] == "maen"

    # A multibyte column earlier in the buffer moves the two currencies apart:
    # the parser reports BYTES (`é` is two) and the editor counts CHARACTERS, so
    # `maen` is bytes 16:19 but chars 15:18. Note the assertion indexes with
    # `collect` — plain `s[range]` is byte indexing, which is the very confusion
    # this conversion exists to absorb.
    buf = "sum(région) + maen(sales)"
    d2 = TW._spec_analyze(:aggr, cols, buf, nothing)
    @test d2.span == 15:18
    @test String(collect(buf)[d2.span]) == "maen"
    # …and the character range is what the editor's own edit primitive wants
    ed = TW.InlineEditor(String; width = 40)
    TW.editor_insert!(ed, buf)
    TW.editor_replace_range!(ed, first(d2.span), last(d2.span), "mean")
    @test ed.buffer == "sum(région) + mean(sales)"

    # an unplaceable span degrades to no squiggle rather than throwing
    @test TW._spec_span_chars("abc", 90:99) === nothing
end

@testset "quiet while typing" begin
    cols = [:region, :sales, :date, :wt]
    an(s) = TW._spec_analyze(:aggr, cols, s, nothing)
    q(s, cur; committed = false) = TW._spec_quiet(an(s), s, cur; committed = committed)

    # Typing one CORRECT spec passes through mostly-rejected intermediate states
    # (17 of the 21 prefixes below are errors); not one of them may shout. This
    # is the whole point of the rule, so it is asserted over the real sequence
    # rather than over hand-picked examples.
    typed = "sum(_ * wt) / sum(wt)"
    for i in 1:length(typed)
        p = typed[1:i]
        d = an(p)
        d.ok || @test TW._spec_quiet(d, p, i + 1)   # caret at the end, as when typing
    end
    # …including the repeated-token case: at "sum(_ * wt) / sum" the parser
    # blames the FIRST `sum`, which is nowhere near the caret
    let p = "sum(_ * wt) / sum"
        @test an(p).span == 1:3                    # first occurrence, per the locator
        @test TW._spec_quiet(an(p), p, length(p) + 1)
    end

    # …but the same text with the caret elsewhere is a real error
    @test !q("maen(_)", 9)
    @test q("maen(_)", 5)             # caret just past 'maen' → still typing it
    @test q("maen(_)", 2)             # caret inside it

    # an incomplete parse is quiet wherever the caret is
    @test q("sum(", 1) && q("sum(", 5)

    # a refused commit ends the politeness, for both classes
    @test !q("sum(", 5; committed = true)
    @test !q("maen(_)", 5; committed = true)

    # a valid spec is never "quiet" — there is nothing to be quiet about
    @test !q("sum(sales)", 1)
end

@testset "diagnostic panel" begin
    cols = [:region, :sales, :date]
    panel(s, cur; committed = false, w = 58, h = 4) =
        TW._spec_panel(:aggr, cols, s, w, h; cursorPos = cur, committed = committed)
    txt(rows) = String[first(r) for r in rows]

    # the action bar is ALWAYS the last row, whatever the message does
    for (s, cur) in (("", 1), ("sum(sales)", 11), ("maen(_)", 9), ("sum(", 5))
        rows = panel(s, cur)
        @test length(rows) == 4
        @test occursin("F6 details", last(txt(rows)))
    end

    # assertive: ✗, and Ctrl-F advertised with the replacement it will apply
    a = txt(panel("maen(_)", 9))
    @test startswith(a[1], "✗")
    @test occursin("Ctrl-F fix→mean", a[end])

    # quiet: same words, dim register, and no repair offered for a token the
    # user is still in the middle of typing
    qt = txt(panel("maen(_)", 5))
    @test startswith(qt[1], "…")
    @test !occursin("Ctrl-F", qt[end])
    @test occursin("did you mean 'mean'", qt[1])     # the message still shows

    @test startswith(txt(panel("sum(sales)", 11))[1], "✓")
    @test startswith(txt(panel("", 1))[1], "→")

    # a message longer than the panel is ellipsised, not cut mid-sentence
    long = txt(panel("cumsum(sales)", 99; w = 30))
    @test endswith(long[3], "…")

    # the panel is colour-coded by severity, not just glyph-coded
    @test last(panel("maen(_)", 9)[1]) == TW.theme(:negative)
    @test last(panel("maen(_)", 5)[1]) == TW.theme(:divider)
end

@testset "host trims boilerplate, never rewords" begin
    m = "parseaggr: unknown function 'maen' -- did you mean 'mean'? " *
        "(listops() shows the whitelist; hosts can extend it with registerop!.) " *
        "[in aggr\"maen(_)\"]"
    t = TW._spec_user_msg(m, "maen(_)")
    @test t == "unknown function 'maen' -- did you mean 'mean'?"   # sentence intact

    # checkcols names its spec inline instead of tagging it — same redundancy
    c = TW._spec_user_msg(
        "checkcols: spec \"sum(salse)\" references column 'salse', which does not exist", "sum(salse)")
    @test c == "references column 'salse', which does not exist"

    # nothing to trim → unchanged
    @test TW._spec_user_msg("plain message", nothing) == "plain message"
end

@testset "editor marks a character range, clipped to the scrolled view" begin
    ed = TW.InlineEditor(String; width = 10)
    TW.editor_insert!(ed, "sum(salse)")
    ed.fieldLeftPos = 1
    @test TW.editor_visible_range(ed, 5:9) == 5:9          # fully visible
    ed.fieldLeftPos = 4                                    # scrolled right
    @test TW.editor_visible_range(ed, 5:9) == 2:6
    ed.fieldLeftPos = 8                                    # span partly off the left
    @test TW.editor_visible_range(ed, 5:9) == 1:2
    ed.fieldLeftPos = 40                                   # scrolled clean past it
    @test TW.editor_visible_range(ed, 5:9) === nothing
    @test ed.highlight === nothing                         # off unless a host asks
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

        @testset "diagnostic panel + squiggle + Ctrl-F, end to end" begin
            df = DataFrame(region = ["E"], sales = [1])
            e = newTwSpecEntry(rootTwScreen, :aggr; key = :m, coltypes = df,
                               width = 60, title = "Aggr: ")
            ed = e.data.editor
            # 2 border + 1 field + 4 panel rows
            @test e.height == 7
            @test getfield(e.data, :panelfn) !== nothing
            @test getfield(e.data, :markfn)  !== nothing
            @test getfield(e.data, :fixfn)   !== nothing

            TW.editor_set_buffer!(ed, "sum(salse)")
            ed.cursorPos = 1                       # caret away from the bad token
            rows = getfield(e.data, :panelfn)(ed.buffer, 58, 4)
            @test length(rows) == 4
            @test startswith(first(rows[1]), "✗")
            @test occursin("Ctrl-F fix→sales", first(rows[end]))

            # draw is what installs the squiggle (via markfn)
            TW.draw(e)
            @test ed.highlight == 5:9
            @test String(collect(ed.buffer)[ed.highlight]) == "salse"

            # the key is advertised only while there is something to repair…
            @test occursin("Ctrl-F:fix", TW.footer(e))
            # …and applying it produces a spec that parses
            @test TW.inject(e, :ctrl_f) == TW.Handled
            @test ed.buffer == "sum(sales)"
            @test TW._spec_valid(:aggr, propertynames(df), ed.buffer)
            TW.draw(e)
            @test ed.highlight === nothing
            @test !occursin("Ctrl-F", TW.footer(e))

            # a caret sitting on the token keeps the widget quiet: no squiggle,
            # no repair offer, even though the same text is a hard error later
            TW.editor_set_buffer!(ed, "maen(sales)")
            ed.cursorPos = 5
            TW.draw(e)
            @test ed.highlight === nothing
            @test TW._entry_pending_fix(e) === nothing
            @test TW.inject(e, :ctrl_f) == TW.Ignored   # unbound while quiet

            # …until a refused commit says the user is done
            @test TW.inject(e, :enter) == TW.Handled    # validator refuses
            TW.draw(e)
            @test ed.highlight == 1:4
            @test TW.inject(e, :ctrl_f) == TW.Handled
            @test ed.buffer == "mean(sales)"

            TW.unregisterTwObj(rootTwScreen, e)
        end

        @testset "short field label, context on the top border" begin
            df = DataFrame(region = ["E"], score = [1])
            e = newTwSpecEntry(rootTwScreen, :aggr; coltypes = df, target = :score,
                               width = 60)
            # the field label names the KIND and stays short…
            @test e.title == "Aggr spec: "
            # …and the target column rides the border instead
            @test getfield(e.data, :boxtitle) == "score"

            # which is the point: input width is what a long label costs. The
            # old label ("Aggr for score (blank=default): ") was 32 columns.
            (fieldcount, _) = TW.getFieldDimension(e)
            @test fieldcount == 60 - length("Aggr spec: ") - 2
            @test fieldcount > 60 - 32 - 2

            # a :dim entry has no target, so no border caption unless asked
            d = newTwSpecEntry(rootTwScreen, :dim; coltypes = df)
            @test d.title == "Dim spec: "
            @test getfield(d.data, :boxtitle) == ""
            d2 = newTwSpecEntry(rootTwScreen, :dim; coltypes = df, boxtitle = "my_dim")
            @test getfield(d2.data, :boxtitle) == "my_dim"

            # an over-long caption is truncated to fit between the corners
            # rather than overwriting them
            w = newTwSpecEntry(rootTwScreen, :aggr; coltypes = df, width = 20,
                               boxtitle = repeat("x", 80))
            @test length(TW.ensure_length(getfield(w.data, :boxtitle), w.width - 4, false)) <= w.width - 4
            TW.draw(w)     # must not throw or overrun the border

            foreach(x -> TW.unregisterTwObj(rootTwScreen, x), (e, d, d2, w))
        end

        @testset "one border slot: boxtitle and titleLeft=false agree" begin
            # `titleLeft = false` and `boxtitle` are the same idea found twice —
            # get the label out of the input's way. They now feed ONE writer to
            # row 0 instead of two that silently overwrote each other.
            cap = "node — date or tenor (?=calendar)"

            # the legacy spelling (ICJ's showclassview.jl uses it): the field's
            # own title relocates to the border, input keeps the full width
            legacy = newTwEntry(rootTwScreen, String; width = 44, title = cap,
                                titleLeft = false)
            # the explicit caption: same width outcome, no inline label
            explicit = newTwEntry(rootTwScreen, String; width = 44, title = "",
                                  boxtitle = cap)
            @test TW.getFieldDimension(legacy)[1] == TW.getFieldDimension(explicit)[1]
            @test TW.getFieldDimension(legacy)[1] == 44 - 2

            # …and an inline label still costs its own width, which is the whole
            # reason the border slot exists
            inline = newTwEntry(rootTwScreen, String; width = 44, title = cap)
            @test TW.getFieldDimension(inline)[1] < TW.getFieldDimension(legacy)[1]

            # both may be set without either being lost to an overwrite: the
            # explicit caption wins the border, the inline label stays inline
            both = newTwEntry(rootTwScreen, String; width = 44, title = "Spec: ",
                              boxtitle = "score")
            @test getfield(both.data, :boxtitle) == "score"
            @test both.data.titleLeft && both.title == "Spec: "
            @test TW.getFieldDimension(both)[1] == 44 - length("Spec: ") - 2

            foreach(x -> (TW.draw(x); TW.unregisterTwObj(rootTwScreen, x)),
                    (legacy, explicit, inline, both))
        end

        @testset "hintheight = 1 keeps the single-row hint" begin
            df = DataFrame(region = ["E"], sales = [1])
            e = newTwSpecEntry(rootTwScreen, :aggr; coltypes = df, hintheight = 1)
            @test getfield(e.data, :panelfn) === nothing   # falls back to hintfn
            @test e.height == 4                            # 2 border + field + 1 hint
            @test startswith(e.data.hintfn("sum(sales)"), "✓")
            TW.unregisterTwObj(rootTwScreen, e)
        end
    finally
        TW.endsession()
    end
end

println("spec_entry_unit.jl: all tests passed.")
