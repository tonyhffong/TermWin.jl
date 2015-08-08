# TermWin.jl

[![TermWin](http://pkg.julialang.org/badges/TermWin_release.svg)](http://pkg.julialang.org/?pkg=TermWin&ver=0.3)
[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate tree-like data structure such as `Expr`, `Dict`, `Array`, `Module`, and
`DataFrame`
It uses a ncurses-based user interface.
It also contains a backend framework for composing ncurses user interfaces.

It requires color support, `xterm-256color` strongly encouraged.

Most viewers have help text via the `F1` key.

The advantages of using TermWin compared to other established GUI framework are that
* Minimal binary dependency. It just depends on ncurses binary, which is widely available. You may be
connecting to a machine via ssh and you can still gain productivity using TermWin.
* light-weight. We leave more resources for other intensive tasks. Useful if we need to examine large data.
* efficiency. We try to emphasize keyboard shortcuts so users can be highly productive after
  investing a bit of time. Also, as an open source julia module, it is quite easy to get close to
  the data and to be cleverer about using the information only when we need them (such as dataframe aggregations).
* Aesthetically flexible. Everything on screen is a utf8 code point, so it is easy to get something
  working, and then improve by using fancier code points. With
  unicode-capable & color terminals being quite common these days, the visual can be excellent.
* old-school-cool

For most users, the main function is `tshow`, which accepts almost anything, and should give you
a fairly usable interactive representation.

### Expr
```julia
using TermWin
ex = :( f(x) = x*x + 2x + 1 )
tshow(ex)
```
![expression](https://cloud.githubusercontent.com/assets/7191122/5458271/62ae80c0-8583-11e4-8ebb-a996d0d63f5e.png)

### Module

An excellent example of looking at modules is to see the `TermWin` module itself:
```julia
using TermWin
tshow( TermWin ) # to see what functionalities it implements
```

### Functions and Methods
To show `Function` and `MethodTable`,
```julia
using TermWin
tshow( deleteat! ) # searchable, pivotable methods table
tshow( methods( deleteat! ) ) # ditto
tshow( methodswith( Set ) )
```

### DataFrames

To show a dataframe, this is the minimum:
```julia
using TermWin
df = DataFrame( a = [1,2], b = ["c", "d"] )
tshow( df )
```

TermWin supports a wide range of configurations in showing dataframes. Here is a rather elaborate example:
```julia
using TermWin
using RDatasets
using Compat

df = dataset( "Ecdat", "Caschool" )
tshow( df;
    colorder = [ :EnrlTot, :Teachers, :Computer, :TestScr, :CompStu, "*" ],
    pivots = [ :County, :top5districts, :District ],
    initdepth = 2,
    aggrHints = @compat(Dict{Any,Any}(
        :TestScr => :( mean( :_, weights(:EnrlTot) ) ),
        :ExpnStu => :( mean( :_, weights(:EnrlTot) ) ),
        :CompStu => :( mean( :_, weights(:EnrlTot) ) ),
        :Str     => :( mean( :_, weights(:EnrlTot) ) )
        ) ),
    calcpivots = @compat( Dict{Symbol,Any}(
        :CountyStrBuckets     => CalcPivot( :(discretize( :Str, [ 14,16,18,20,22,24 ], rank = true, compact = true )), :County ),
        :CountyTestScrBuckets => CalcPivot( :(discretize( :TestScr, [ 600, 620, 640, 660, 680, 700],
                                    label = "score", rank = true, compact = false, reverse = true ) ), :County ),
        :top5districts        => CalcPivot( :(topnames( :District, :TestScr, 5 ) ) )
        ) ),
    views = [
        @compat(Dict{Symbol,Any}( :name => "ByStr",       :pivots => [ :CountyStrBuckets, :County, :District] ) ),
        @compat(Dict{Symbol,Any}( :name => "ByTestScr",   :pivots => [ :CountyTestScrBuckets, :County, :District] ) ),
        @compat(Dict{Symbol,Any}( :name => "Top5Schools", :pivots => [ :top5districts, :County ] ) )
    ],
    )
```

which will generate this output:

![caschool](https://cloud.githubusercontent.com/assets/7191122/5457618/8f136f72-857e-11e4-8a27-5c4666f0386b.png)

Here the "top5district" pivot (after County) is a "calculated pivot". It is not static.
It is generated based on the path of the tree nodes, so
as the user moves this pivot further up or down the pivot chain, the
ranking would be adjusted to the context/subdataframe
correctly. Another example of calculated pivot is discretization on aggregated values "CountyTestScrBuckets",
which can be found on the view selector ('v' keyboard shortcut) in the same example.
You can also change the pivot ordering without restarting the view using the 'p' shortcut.

Also, note that aggregation `aggrHints` is done via an expression that will be lifted into a compiled function. The
argument column `:_` is always replaced with the column name at compilation.
Other required columns for the aggregation function (such as weights in this case) must be explicitly
named. The convention of using colons to denote columns follows 
[DataFramesMeta.jl](https://github.com/JuliaStats/DataFramesMeta.jl)

The dataframe viewer supports a large range of options:

* `pivots`. Array of `Symbol`. They can be a **calcpivot**. (see below)
* `initdepth`. Default 1. How many levels of pivots are open at initialization.
* `colorder`. Array of `Symbol`, `Regex` and `"*"` (string). Symbols are treated as actual column name.
   It is an error to provide a symbol that doesn't exist as a column in the data frame. Regex would
   be used to to match multiple columns. `"*"` is the rest of the columns not covered yet. It is
   permissible to put `"*"` in the middle of the array, but it is NOT ok to include two or more `"*"`.
* `hidecols`. Array of `Symbol` and `Regex`. Columns that match these will be hidden. This overrules
  `colorder`.
* `sortorder`. Array of `(Symbol, Symbol)`, the first is the column name, the second is either `:asc` or `:desc`.
   If only a `Symbol[]` is provided, all are assumed in `:asc` order
* `title`.
* `formatHints`. `Dict{Any,FormatHints}`. Keys of `Symbol` type are treated as column names. Keys of `DataType`
   are backup formats when actual format hints for a name are not provided.
* `widthHints`. `Dict{Symbol,Int}`. If present, the width will override default in formatHints.
* `aggrHints`. `Dict{Any,Any}`. Keys of `Symbol` type are treated as column names. Keys of `DataType`
   are backup aggregation hints when actual aggregation hints for a name are not provided. The values
   can be strings like `"mean"`, or `"mean(:_, :wtcol)"`, equivalent symbols or expressions
   e.g. `:( mean(:_, weights( :wtcol ) ) )`, etc. Quoted symbols are interpreted as columns, similar to how
   `DataFramesMeta` package.
* `calcpivots`. Dynamic pivotable quantity. This generates a computed column that can be included
   in the `pivots` above.
* `headerHints`. Alternative name for the header.
* `views`. Array of Dictionaries that provide alternative views of the same data. Overrideable keys are
    * `pivots`, `colorder`, `hidecols`, `sortorder`, `initdepth` with the same meaning as above.
    * `name`. String. name of the view. If not provided the views would just be `v#1`, `v#2`, and so on...

TermWin provides a few commonly used aggregation functions for table data presentation:

* `uniqvalue`. If all non-NA values are the same, use that value, otherwise NA. For strings, empty strings
   are treated as NA (i.e. ignored) as well. This is the default aggregation for string typed columns.
* `unionall`. If the column's element-type is an array, union them all. This is the default aggregation for
  array typed columns.

On **CalcPivot**, TermWin provides
* `discretize`. It needs `:measure` column and a break vector. Similar to `cut`, with the following options
   * leftequal. Default true, meaning the boundary values are interpreted as `t1 ≤ x < t2`
   * boundedness. Symbol. Default `:unbounded`.
       * `:unbounded`. We group all numbers below the first break and above the last break into their
         respective categories.
       * `:bounded`. All numbers less than the first break and more than the last break will become `NA`
       * `:boundedbelow`. All numbers less than the first break will become `NA`
       * `:boundedabove`. All numbers more than the last break will become `NA`
   * absolute. Default false. If true, bucketing test would becomes `t1 ≤ |x| < t2`
   * rank. Default true. Output bucket strings are prefixed with consecutive numbers to make them easier to sort.
   * ranksep. Default ". ". The string between the rank number and the range description
   * label. Default is an empty string. If set, it is expected we want to show the long-form range description
e.g. `t1 ≤ x < t2`
   * compact. Default is true. Compact range looks terser, like `[1,5)`. Integers range with interval size 1
     is further compacted to just that number.
   * reverse. Default is false. If set to true, the higher ranges come first.
   * prefix, suffix, scale, precision, commas, stripzeros, parens, mixedfraction, autoscale, conversion. These are options from `Formatting.jl`
   * ngroups. **Default to 4 when breaks are not provided**. Generate breaks based on number of groups.
* `topnames`. It requires a `:name` column, a `:measure` column and an integer (typically small). Keyward arguments
  include:
   * absolute. Default false. If true, large negatives will be included in the top names too. Please note that
   the sort order will always put negative values below positive ones. See `test/dftests.jl` for more details.
   * ranksep. Default ". ".
   * dense = true. Whether it skip numbers when encountering ties.
   * tol. Tolerance. Default zero. If set positive and absolute is true, measures that are below this
      tolerance threshold will not be included, no matter what.
   * others. Default "Others". How data not in the top N will look like.
   * parens. Default false. If the measure is negative and this is set, parentheses will be added around
     the name.

## Other usage tips

`tshow` for most types accepts at a minimum the following keyword arguments:
* title
* height. When floating point, it must be within [0.0, 1.0] i.e. relative screen size. When integer, they mean character height.
* width. ditto
* posx. When integer, it is the x (horizontal) location. 0 is the left edge. It also supports symbols such as
    * `:staggered`
    * `:center`
    * `:left`
    * `:right`
    * `:random`
* posy. When integer, it is the y (vertical) location. 0 is the top edge.
    * `:staggered`
    * `:center`
    * `:top`
    * `:bottom`
    * `:random`

`tshow` returns the widget which can be re-shown. This is especially useful with the dataframe and other
container viewers, which remember the pivot states, the column order, etc.

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

### Input Widgets

Numeric, text, date input field (See `test/twentry.jl`). Designed to maximize
entry efficiency and accuracy (See F1 help screen).
UTF-8 input and output are supported with correct cursor movement.
Most European typesets,
Han characters, Thai (with compound vowel issues),
currency symbols, e.g. €, £, are fine..

It supports date type

### Examples:

Getting a value or a string from a user:
```julia
```

One out of many selection:
```julia
```

Getting a multi-value selection:
```julia
```

### General comments on code organization

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

### Focus and keystroke traffic logic
When a widget has the focus, it has first dip in interpreting any user
keystroke. Only when the widget gives up (by returning `:pass`), the container
(usually `TwScreen`) looks for other widgets also in play (when they have
grabUnusedKeys set to true, e.g. Menu). After all widgets pass, then the
container would try to interpret it itself. If a widget return :exit_ok, it’s
instructing the container that it has got what it wanted. The container
may still choose to switch focus, or exit -- the inject function would need
to be overriden to tell TermWin what to do.
