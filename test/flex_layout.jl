# flex_layout.jl — demonstrates the flexible sizing hints :content / :fill / Flex
#
# Sizing hints supplement the literal height=/width= arguments in vstack/hstack:
#   :content   → size to the widget's natural content extent
#   :fill      → grow to consume the leftover main-axis space (weight 1)
#   Flex(w)    → like :fill, but split the leftover space by relative weight w
#
# Usage:
#   julia --project=. test/flex_layout.jl
#
# Three demos run in sequence — press Esc to advance between them:
#   1. vstack: a header + a :content tree (shrinks to its rows) + a :fill tree
#      (takes all the remaining vertical space — resize the terminal taller and
#      it grows to match).
#   2. hstack (root): two trees splitting the width 2:1 via Flex(2) / Flex(1).
#   3. vstack: a :content viewer over a long :fill tree that scrolls.

using TermWin

shorttree = Dict("alpha" => 1, "beta" => 2, "gamma" => 3)
bigtree = Dict(
    "config"  => Dict("host" => "localhost", "port" => 8080, "tls" => true),
    "metrics" => Dict("p50" => 12.4, "p95" => 88.1, "p99" => 240.0),
    "users"   => ["alice", "bob", "carol", "dave", "erin", "frank", "grace"],
    "flags"   => Dict("a" => true, "b" => false, "c" => true, "d" => false),
)

# ── Demo 1: vstack — :content over :fill ─────────────────────────────────────
struct _FlexVStackDemo end
function TermWin.tshow_(::_FlexVStackDemo; title = "", kwargs...)
    vstack(; title = title, height = 40, width = 80) do s
        newTwLabel(s, "header (height=1)"; style = :header)
        newTwTree(s, shorttree; height = :content, title = "shorttree  (height=:content)")
        newTwTree(s, bigtree;   height = :fill,    title = "bigtree  (height=:fill — takes the rest)")
    end
end
tshow(_FlexVStackDemo(); title = ":content + :fill in a vstack  (Esc to advance)")

# ── Demo 2: root hstack — width split 2:1 via Flex ───────────────────────────
struct _FlexHStackDemo end
function TermWin.tshow_(::_FlexHStackDemo; title = "", kwargs...)
    hstack(; title = title, height = 40, width = 80) do s
        newTwTree(s, bigtree;   width = Flex(2), title = "Flex(2)")
        newTwTree(s, shorttree; width = Flex(1), title = "Flex(1)")
    end
end
tshow(_FlexHStackDemo(); title = "Flex(2)/Flex(1) width split in a root hstack  (Esc to advance)")

# ── Demo 3: vstack — :content viewer over a scrolling :fill tree ──────────────
struct _FlexViewerDemo end
function TermWin.tshow_(::_FlexViewerDemo; title = "", kwargs...)
    summary = "This viewer is height=:content — it sizes to its 3 lines,\n" *
              "leaving the rest of the column to the tree below (height=:fill),\n" *
              "which scrolls when its content exceeds the space it is given."
    vstack(; title = title, height = 40, width = 80) do s
        newTwViewer(s, summary; height = :content, box = true, title = "summary (:content)")
        newTwTree(s, bigtree;   height = :fill, title = "details (:fill)")
    end
end
tshow(_FlexViewerDemo(); title = ":content viewer + :fill tree  (Esc to advance)")

# ── Demo 4: nested flex — root hstack of two vstack columns ───────────────────
# Perpendicular nesting: the columns split the WIDTH 2:1 (Flex on the hstack),
# and inside each column a :content header sits over a :fill tree that fills the
# column's full HEIGHT. This is the case that only works once flex is honored
# inside nested vstack/hstack.
struct _FlexNestedDemo end
function TermWin.tshow_(::_FlexNestedDemo; title = "", kwargs...)
    hstack(; title = title, height = 40, width = 90) do s
        vstack(s; width = Flex(2)) do col
            newTwLabel(col, "left column — Flex(2)"; style = :header)
            newTwTree(col, bigtree; height = :fill, title = "fills column height")
        end
        vstack(s; width = Flex(1)) do col
            newTwLabel(col, "right — Flex(1)"; style = :header)
            newTwTree(col, shorttree; height = :fill, title = "fills column height")
        end
    end
end
tshow(_FlexNestedDemo(); title = "nested flex: columns split width 2:1, trees fill height  (Esc to exit)")
