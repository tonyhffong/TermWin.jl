# TermWin.jl

[![TermWin](http://pkg.julialang.org/badges/TermWin_release.svg)](http://pkg.julialang.org/?pkg=TermWin&ver=0.3)
[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate tree-like data structure such as `Expr`, `Dict`, `Array`, `Module`, and
`DataFrame`
It uses a ncurses-based user interface.
It also contains a backend framework for composing ncurses user interfaces.

It requires color support, preferably `xterm-256color`.

Most viewers have help text via the `F1` key.

### Expr
```julia
using TermWin
ex = :( f(x) = x*x + 2x + 1 )
tshow(ex)
```

### Functions and Methods
For `Function` and `MethodTable`, this would show a searchable (fuzzy) window, based on
a mixture of substring search and Levenstein edit distance:
```julia
using TermWin
tshow( deleteat! ) # searchable methods table
tshow( methods( deleteat! ) ) # ditto
tshow( methodswith( Set ) ) # searchable, too!
```


### DataFrame

TermWin supports a wide range of configurations in showing dataframes, for example:
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

* `pivots`. Array of `Symbol`. They can be a **calcpivot**. (see below)
* `initdepth`. Default 1. How many levels of pivots are open at initialization.
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
* `aggrHints`. `Dict{Any,Any}`. Keys of `Symbol` type are treated as column names. Keys of `DataType`
   are backup aggregation hints when actual aggregation hints for a name are not provided. The values
   can be strings like `"mean"`, or `"mean(:_, :wtcol)"`, equivalent symbols or expressions
   e.g. `:( mean(:_, weights( :wtcol ) ) )`, etc. Quoted symbols are interpreted as columns, similar to how
   `DataFramesMeta` package.
* `calcpivots`. Dynamic pivotable quantity. This generates a computed column that can be included
   in the `pivots` above. This is useful when the desired pivotable values depend on the pivots
   up to the point where we need them. In other words they are not static. For example,
   * the top district by the average test score would depend on whether we pivot by county first, or
      nothing (i.e. the top districts in the entire data set).
   * In addition, the data may be in `district x test x testscore` format. In other words, there may be multiple
     test scores per district So we must provide the aggregation rule (e.g. mean) and group-by
     granularity (student in this case). Aggregation rule is done by the same aggrHints above.
     Granularity is provided using the `by` keyword argument in the CalcPivot type constructor.
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
* `discretize`. Similar to `cut`, with the following options
* `topnames`.


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

Numeric and text input field (See `test/twentry.jl`). Designed to maximize
entry efficiency and accuracy (See F1 help screen).
UTF-8 input and output are supported. That said, in an entry field,
cursor movements may produce dodgy behavior if typing order and visual order
can be different e.g. Thai's prefix-vowels. Most European typesets,
Han characters, currency symbols, e.g. €, £, are fine.

It supports date type

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
