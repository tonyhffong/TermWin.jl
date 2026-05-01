# formlayout_edittable.jl — composite data-entry screen: header fields + editable table
#
# Scenario: Sales Order Entry
#   Header fields : Customer name, order date, sales region (scalar entry/popup widgets)
#   Order lines   : Editable table — product (enum), qty, unit price, notes
#
# The whole screen is a single @twlayout form.  Pressing F10 collects every
# keyed widget's value into a Dict{Symbol,Any}:
#   :customer   => String
#   :order_date => Date
#   :region     => String
#   :lines      => DataFrame  (the live, edited table)
#
# Usage:
#   julia --project=. test/formlayout_edittable.jl
#
# Controls:
#   Tab / Shift-Tab  : move focus between widgets
#   Arrow keys       : navigate cells inside the table
#   Ctrl-N           : insert a new order line after the current row
#   Ctrl-D           : delete the current order line
#   Enter            : move down (table) / advance to next field (header fields)
#   F10              : submit form → prints the collected order
#   Esc              : cancel
#   F1               : help for the focused widget

using TermWin, DataFrames, Dates, Printf

# ── Column definitions for the order-line table ───────────────────────────────

const PRODUCTS = ["Widget A", "Gadget B", "Doohickey C", "Thingamajig D", "Gizmo E"]

const ORDER_LINE_COLS = [
    TwEditTableCol(:product,   "Product",    16, true,  String,  PRODUCTS),
    TwEditTableCol(:qty,       "Qty",         6, true,  Int,     nothing),
    TwEditTableCol(:unitprice, "Unit Price", 11, true,  Float64, nothing),
    TwEditTableCol(:notes,     "Notes",      22, true,  String,  nothing),
]

# ── Seed data (two starter lines so the table isn't empty) ────────────────────

seed_lines = DataFrame(
    product   = ["Widget A",  "Gadget B"],
    qty       = [10,           5        ],
    unitprice = [99.50,        249.00   ],
    notes     = ["",           "fragile"],
)

# ── Option A: @twlayout macro (primary) ──────────────────────────────────────

TermWin.initsession()

form = @twlayout :vertical (
    form    = true,
    title   = "Sales Order",
    height  = 0.88,
    width   = 0.68,
    defaults = Dict{Symbol,Any}(:order_date => today()),
) begin

    label("Order Header"; style=:header)
    entry(String; key=:customer,   title="Customer",   width=36, titlewidth=12)
    entry(Date;   key=:order_date, title="Order Date", width=36, titlewidth=12)
    popup(["North", "South", "East", "West"];
          key=:region, title="Region", maxheight=4)

    label("Order Lines  (Ctrl-N: new row · Ctrl-D: delete row)"; style=:divider)
    edittable(seed_lines, ORDER_LINE_COLS; key=:lines, height=0.5)

end

activateTwObj(rootTwScreen)
result = form.value
TermWin.endsession()

# ── Option B: vstack / hstack (uncomment to use instead of Option A) ──────────
#
# TermWin.initsession()
#
# form = vstack(; form=true, title="Sales Order", height=0.88, width=0.68,
#               defaults=Dict{Symbol,Any}(:order_date => today())) do parent
#     newTwLabel(parent, "Order Header"; style=:header)
#     newTwEntry(parent, String; key=:customer,   title="Customer",   width=36, titlewidth=12)
#     newTwEntry(parent, Date;   key=:order_date, title="Order Date", width=36, titlewidth=12)
#     newTwPopup(parent, ["North","South","East","West"];
#                key=:region, title="Region", maxheight=4)
#     newTwLabel(parent, "Order Lines  (Ctrl-N: new row · Ctrl-D: delete row)";
#                style=:divider)
#     newTwEditTable(parent, seed_lines, ORDER_LINE_COLS; key=:lines, height=0.5)
# end
#
# activateTwObj(rootTwScreen)
# result = form.value
# TermWin.endsession()

# ── Display results ───────────────────────────────────────────────────────────

if result === nothing
    println("Order cancelled.")
else
    println("Order submitted:")
    println()
    @printf("  Customer   : %s\n", get(result, :customer, ""))
    @printf("  Order Date : %s\n", get(result, :order_date, ""))
    @printf("  Region     : %s\n", get(result, :region, ""))
    println()
    println("  Order Lines:")

    hdr = @sprintf("  %-16s  %6s  %11s  %s", "Product", "Qty", "Unit Price", "Notes")
    println(hdr)
    println("  ", repeat("─", length(hdr) - 2))

    df = get(result, :lines, seed_lines)
    for row in eachrow(df)
        @printf("  %-16s  %6d  %11.2f  %s\n",
                row.product, row.qty, row.unitprice, row.notes)
    end

    total = sum(row.qty * row.unitprice for row in eachrow(df); init=0.0)
    println("  ", repeat("─", 38))
    @printf("  %-16s  %6s  %11.2f\n", "TOTAL", "", total)
end
