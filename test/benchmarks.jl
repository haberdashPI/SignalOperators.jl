using BenchmarkTools
using SignalOperators
using SignalOperators.Units
using Random

suite = BenchmarkGroup()

rng = MersenneTwister(1983)
x = rand(rng,10^5,2)
y = rand(rng,10^5,2)

suite["signal mapping"] = @benchmarkable sink(mix($x,$y),samplerate=1000Hz)
suite["baseline mapping"] = @benchmarkable $x .+ $y

paramspath = joinpath(@__DIR__,"params.json")

if isfile(paramspath)
    loadparams!(suite, BenchmarkTools.load(paramspath)[1], :evals)
else
    tune!(suite)
    BenchmarkTools.save(paramspath, params(suite))
end

result = run(suite)
