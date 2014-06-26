# TermWin.jl

[![Build Status](https://travis-ci.org/tonyhffong/TermWin.jl.svg?branch=master)](https://travis-ci.org/tonyhffong/TermWin.jl)

## Introduction

TermWin.jl is a tool to help navigate deep data structure such as `Expr`, `Dict`, `Array`, `Module`. It uses a very
minimalist ncurses-based user interface.

## Installation
```julia
Pkg.add( "TermWin" )
```

## Usage

The key function is `tshow`. You should be able to use it on almost anything.
```
using TermWin
ex = :( f(x) = x*x + 2x + 1 )
tshow(ex)
```
