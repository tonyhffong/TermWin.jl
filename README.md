# TermWin.jl

[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate deep data structure such as `Expr`, `Dict`, `Array`, `Module`. It uses a very
minimalist ncurses-based user interface.
```julia
using TermWin
ex = :( f(x) = x*x + 2x + 1 )
tshow(ex)
```

For `Function` and `MethodTable`, this would show a searchable (fuzzy) window:
```julia
using TermWin
tshow( deleteat! ) # searchable methods table
tshow( methods( deleteat! ) ) # ditto
tshow( methodswith( Set ) ) # searchable, too!
```

## Installation
```julia
Pkg.add( "TermWin" )
```

