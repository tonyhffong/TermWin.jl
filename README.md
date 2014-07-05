# TermWin.jl

[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate deep data structure such as `Expr`, `Dict`, `Array`, `Module`.
It uses a ncurses-based user interface.
It also contains a backend framework for composing ncurses user interfaces.

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

Mouse support.

Color support.

## Installation

As stated on the tin, TermWin requires ncurses. It is being developed on MacOS/iTerm.
It also requires Lint.jl for a superficial code cleanliness test. (Not sure how
to unit-test a GUI than actually using it manually.)
```julia
Pkg.add( "TermWin" )
```

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
