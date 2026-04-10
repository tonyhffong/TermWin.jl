using TermWin, DataFrames, StatsBase
df = DataFrame(TestScr = [1.0, 2.0, 3.0, 4.0],
               EnrlTot = [10.0, 20.0, 30.0, 40.0])

# New, StatsBase-correct wmean_instruction
wmean_instruction = :( StatsBase.mean( :_, StatsBase.Weights(:EnrlTot) ) )
f = TermWin.liftAggrSpecToFunc(:TestScr, wmean_instruction)
got = f(df)
expected = StatsBase.mean(df.TestScr, StatsBase.Weights(df.EnrlTot))
println("got      = ", got)
println("expected = ", expected)
@assert got ≈ expected
println("OK: nested-dot StatsBase.mean(:_, StatsBase.Weights(:EnrlTot)) lifts")
