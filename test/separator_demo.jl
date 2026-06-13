# separator_demo.jl — demonstrates newTwSeparator inside vstack and hstack
#
# A separator auto-sizes to the parent container's orientation:
#   - inside a vstack → full-width horizontal rule (─────)  height=1
#   - inside an hstack → full-height vertical rule (│)       width=1
#
# Usage:
#   julia --project=. test/separator_demo.jl
#
# Two demos run in sequence — press Esc to advance between them:
#   1. vstack with horizontal separators between labelled sections
#   2. hstack with a vertical separator (via @twlayout nested hstack)

using TermWin

# ── Demo 1: vstack — horizontal separators ────────────────────────────────────

struct _SeparatorVStackDemo end

function TermWin.tshow_(::_SeparatorVStackDemo; title = "", kwargs...)
    vstack(; title = title, height=40, width=80) do s
        newTwLabel(s, "Section A"; style = :header)
        newTwLabel(s, "First item in section A")
        newTwLabel(s, "Second item in section A")
        newTwSeparator(s)
        newTwLabel(s, "Section B"; style = :header)
        newTwLabel(s, "First item in section B")
        newTwLabel(s, "Second item in section B")
        newTwSeparator(s)
        newTwLabel(s, "Section C"; style = :header)
        newTwLabel(s, "Only item in section C")
    end
end

tshow(_SeparatorVStackDemo(); title = "vstack separator demo  (Esc to exit)")

# ── Demo 2: hstack — vertical separator via @twlayout nesting syntax ──────────

struct _SeparatorHStackDemo end

function TermWin.tshow_(::_SeparatorHStackDemo; title = "", kwargs...)
    @twlayout (title = title, height = 50, width = 80) begin
        hstack(begin
            label("Left column";  style = :header, width = 20)
            separator()
            vstack(begin
                label("Right column"; style = :header, width = 20)
                separator()
                label("more stuff"; width = 20)
            end)
        end)
    end
end
tshow(_SeparatorHStackDemo(); title = "hstack separator demo  (Esc to exit)")
