# Demonstrates all 31 COLOR_PAIR(n) combinations defined by TermWin.
#
# Run:
#   julia --project=. test/color_pair.jl
#
# Each row shows the pair number, a normal swatch, a bold swatch,
# and a description with the fg/bg colours plus any widget usage note.
# Press Esc to exit.

using TermWin
import TermWin: tshow_, TwAttr, A_BOLD

# ─── layout constants (all in 1-based byte/char positions) ───────────────────

const _NUM_W    = 2   # width of pair-number field
const _GAP      = "   "   # gap between columns (3 spaces)
const _SWATCH   = " AaBbCcDd "  # 10-char swatch; leading/trailing space shows bg
const _SW_LEN   = length(_SWATCH)  # 10

const _NORM_START = _NUM_W + length(_GAP) + 1          #  6
const _NORM_END   = _NORM_START + _SW_LEN - 1          # 15
const _BOLD_START = _NORM_END + length(_GAP) + 1       # 19
const _BOLD_END   = _BOLD_START + _SW_LEN - 1          # 28
const _DESC_START = _BOLD_END + 3                      # 31

# ─── metadata ────────────────────────────────────────────────────────────────

const _PAIR_DESC = [
    "red on black",              #  1
    "green on black",            #  2
    "yellow on black",           #  3
    "blue on black",             #  4
    "magenta on black",          #  5
    "cyan on black",             #  6
    "white on black",            #  7
    "black on bright blue",      #  8
    "red on dark blue",          #  9
    "green on dark blue",        # 10
    "yellow on dark blue",       # 11
    "white on dark red",         # 12
    "white on dark gray",        # 13
    "cyan on dark blue",         # 14
    "white on blue",             # 15
    "black on dark red",         # 16
    "red on dark red",           # 17
    "green on dark red",         # 18
    "yellow on dark red",        # 19
    "blue on dark red",          # 20
    "magenta on dark red",       # 21
    "cyan on dark red",          # 22
    "white on dark red",         # 23
    "light purple on black",     # 24
    "light purple on dark blue", # 25
    "green on dark blue",        # 26
    "yellow on dark blue",       # 27
    "gray on dark blue",         # 28
    "red on dark gray",          # 29
    "white on dark blue",        # 30
    "red on dark blue",          # 31
]

const _PAIR_USAGE = Dict{Int,String}(
    1  => "calendar non-bday, negative values",
    3  => "header labels",
    12 => "invalid input; delete confirmation",
    13 => "divider labels; alternating rows",
    15 => "focused selection highlight",
    30 => "unfocused selection highlight",
)

# ─── build lines + spans ─────────────────────────────────────────────────────

function _build_palette()
    lines = String[]
    spans = Vector{Vector{Tuple{Int,Int,TwAttr}}}()

    # column header
    hdr = repeat(" ", _NORM_START - 1) *
          "normal" *
          repeat(" ", _BOLD_START - _NORM_START - 6) *
          "bold" *
          repeat(" ", _DESC_START - _BOLD_START - 4) *
          "description"
    push!(lines, hdr)
    push!(spans, Tuple{Int,Int,TwAttr}[])

    push!(lines, "")
    push!(spans, Tuple{Int,Int,TwAttr}[])

    for n in 1:31
        desc  = n <= length(_PAIR_DESC) ? _PAIR_DESC[n] : "?"
        usage = get(_PAIR_USAGE, n, "")
        label = isempty(usage) ? desc : desc * "   [" * usage * "]"

        line = lpad(string(n), _NUM_W) * _GAP * _SWATCH * _GAP * _SWATCH * "  " * label
        push!(lines, line)

        attr_n = COLOR_PAIR(n)
        attr_b = COLOR_PAIR(n) | A_BOLD
        push!(spans, Tuple{Int,Int,TwAttr}[
            (_NORM_START, _NORM_END, attr_n),
            (_BOLD_START, _BOLD_END, attr_b),
        ])
    end

    (lines, spans)
end

# ─── tshow_ extension ────────────────────────────────────────────────────────

struct _ColorPaletteDemo end

function tshow_(::_ColorPaletteDemo; title = "COLOR_PAIR Demo", kwargs...)
    (lines, spans) = _build_palette()
    viewer = newTwViewer(rootTwScreen, lines;
        title  = title,
        height = 0.9,
        width  = 0.95,
    )
    viewer.data.colorspans = spans
    registerTwObj(rootTwScreen, viewer)
    viewer
end

# ─── entry point ─────────────────────────────────────────────────────────────

tshow(_ColorPaletteDemo(); title = "COLOR_PAIR Demo  (Esc to exit)")
