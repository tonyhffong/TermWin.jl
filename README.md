# TermWin.jl

[![TermWin](http://pkg.julialang.org/badges/TermWin_release.svg)](http://pkg.julialang.org/?pkg=TermWin&ver=0.3)
[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate deep data structure such as `Expr`, `Dict`, `Array`, `Module`, and
`DataFrame`
It uses a ncurses-based user interface.
It also contains a backend framework for composing ncurses user interfaces.

It requires color support, preferably `xterm-256color`, which should be quite common these days.

Most viewers have help text via the `F1` key.

```julia
using TermWin
ex = :( f(x) = x*x + 2x + 1 )
tshow(ex)
```

For `Function` and `MethodTable`, this would show a searchable (fuzzy) window, based on
a mixture of substring search and Levenstein edit distance:
```julia
using TermWin
tshow( deleteat! ) # searchable methods table
tshow( methods( deleteat! ) ) # ditto
tshow( methodswith( Set ) ) # searchable, too!
```

Numeric and text input field (See `test/twentry.jl`). Designed to maximize
entry efficiency and accuracy (See F1 help screen).
UTF-8 input and output are supported. That said, in an entry field,
cursor movements may produce dodgy behavior if typing order and visual order
can be different e.g. Thai's prefix-vowels. Most European typesets,
Han characters, currency symbols, e.g. €, £, are fine.

Date input support.

Mouse support.

### DataFrame

TermWin supports a wide range of configurations in showing dataframes
```julia
using TermWin
using Compat
tshow( df;
  pivots = [ :col1, :col2 ],
  expanddepth = 2, # default expansion of the pivots
  colorder = [ :col3, :col4, "*", :col5 ],
  aggrHints = @compat(Dict{Any,DataFrameAggr}( Int => DataFrameAggr( "mean" ) ) ),
  views = [
      @compat(Dict{Symbol,Any}( :name => "ByCol2", :pivots => [ :col2, :col1 ], :hidecols => [:col5 ] ) )
  ]
  )
```

* `pivots`. Array of `Symbol`
* `expanddepth`. Default 1. How many levels of pivots are open at initialization.
* `colorder`. Array of `Symbol`, `Regex` and `"*"` (string). Symbols are treated as actual column name.
   It is an error to provide a symbol that doesn't exist as a column in the data frame. Regex would
   be used to to match multiple columns. `"*"` is the rest of the columns not covered yet. It is
   permissible to put `"*"` in the middle of the array, but it is NOT ok to include two or more `"*"`.
* `hidecols`. Array of `Symbol` and `Regex`. Columns that match these will be hidden. This overrules
  `colorder`.
* `sortorder`. Array of `(Symbol, Symbol)`, the first is the column name, the second is either `:asc` or `:desc`.
* `title`.
* `formatHints`. `Dict{Any,FormatHints}`. Keys of `Symbol` type are treated as column names. Keys of `DataType`
   are backup formats when actual format hints for a name are not provided.
* `widthHints`. `Dict{Symbol,Int}`. If present, the width will override default in formatHints.
* `aggrHints`. `Dict{Any,DataFrameAggr}`. Keys of `Symbol` type are treated as column names. Keys of `DataType`
   are backup aggregation hints when actual aggregation hints for a name are not provided.
* `headerHints`. Alternative name for the header.
* `views`. Array of Dictionaries that provide alternative views of the same data. Overrideable keys are
    * `pivots`, `colorder`, `hidecols`, `sortorder`, `expanddepth` with the same meaning as above.
    * `name`. String. name of the view. If not provided the views would just be `v#1`, `v#2`, and so on...

Aggregation is done via `DataFrameAggr` type from this package. TermWin also provides a
list of commonly used aggregation functions for table data presentation:

* `uniqvalue`. If all non-NA values are the same, use that value, otherwise NA. For strings, empty strings
   are treated as NA (i.e. ignored) as well. This is the default aggregation for string typed columns.
* `unionall`. If the column's element-type is an array, union them all. This is the default aggregation for
  array typed columns.

## Installation

As stated on the tin, TermWin requires ncurses. It is being developed on MacOS/iTerm.
It also requires Lint.jl for a superficial code cleanliness test. (Not sure how
to unit-test a GUI than actually using it manually.)
```julia
Pkg.add( "TermWin" )
```

If you are using iTerm2 on MacOS, it is known that its `modern parser` for CSI codes are not
compatible to this package. You should disable it.

## Using TermWin to compose dialogs and ncurses applications

The key type is `TwObj`. It is the type that renders something.
TwScreen is just a typealias for TwObj, but it holds special role in
* directing key stroke traffic
* hold references to the content widgets and update them in the correct order

Many widgets can be used in both blocking and non-blocking manner, though
some are more useful in blocking than non-blocking and others vice versa.

To use a widget for blocking use, instantiate that widget (if a container, 
put them inside too) and call
```julia
return_value = activateTwObj( widget )
```

To use a widget for non-blocking use, you need a container widget that is
actually blocking and put it inside the container. See the function viewer for
an example of mixing in a data entry field.

## Focus and keystroke traffic logic
When a widget has the focus, it has first dip in interpreting any user
keystroke. Only when the widget gives up (by returning `:pass`), the container
(usually `TwScreen`) looks for other widgets also in play (when they have
grabUnusedKeys set to true, e.g. Menu). After all widgets pass, then the
container would try to interpret it itself. If a widget return :exit_ok, it’s
instructing the container that it has got what it wanted. The container
may still choose to switch focus, or exit -- the inject function would need
to be overriden to tell TermWin what to do.
