

using BenchmarkTools
using SignalOperators
using SignalOperators.Units
using Random
using Traceur
using Statistics
using DSP

suite = BenchmarkGroup()
suite["signal"] = BenchmarkGroup()
suite["baseline"] = BenchmarkGroup()

rng = MersenneTwister(1983)
# x = rand(rng,10^1,2)
# y = rand(rng,10^1,2)
x = rand(rng,10^4,2)
y = rand(rng,10^4,2)

suite["signal"]["sinking"] = @benchmarkable signal(x,1000Hz) |> sink
suite["baseline"]["sinking"] = @benchmarkable copy(x)
suite["signal"]["functions"] = @benchmarkable begin
    signal(sin,ω=10Hz) |> sink(duration=10_000samples,samplerate=1000Hz)
end
suite["baseline"]["functions"] = @benchmarkable begin
    sinpi.(range(0,step=1/1000,length=10^4) .* (2*10))
end
suite["signal"]["numbers"] = @benchmarkable begin
    1 |> sink(duration=10_000samples,samplerate=1000Hz)
end
suite["baseline"]["numbers"] = @benchmarkable begin
    ones(10_000)
end

suite["signal"]["cutting"] = @benchmarkable begin
    x |> until(5*10^3*samples) |> sink(samplerate=1000Hz)
end
suite["baseline"]["cutting"] = @benchmarkable x[1:(5*10^3)]
suite["signal"]["padding"] = @benchmarkable begin
    pad($x,zero) |> until(20_000samples) |> sink(samplerate=1000Hz)
end
suite["baseline"]["padding"] = @benchmarkable vcat($x,zero($x))
suite["signal"]["appending"] = @benchmarkable sink(append($x,$y),samplerate=1000Hz)
suite["baseline"]["appending"] = @benchmarkable vcat($x,$y)

suite["signal"]["mapping"] = @benchmarkable sink(mix($x,$y),samplerate=1000Hz)
suite["baseline"]["mapping"] = @benchmarkable $x .+ $y

suite["signal"]["filtering"] = @benchmarkable begin
    lowpass($x,20Hz) |> sink(samplerate=1000Hz)
end
suite["baseline"]["filtering"] = @benchmarkable begin
    filt(digitalfilter(Lowpass(20,fs=1000),Butterworth(5)),$x)
end

paramspath = joinpath(@__DIR__,"params.json")

if isfile(paramspath)
    loadparams!(suite, BenchmarkTools.load(paramspath)[1], :evals)
else
    tune!(suite)
    BenchmarkTools.save(paramspath, params(suite))
end

result = run(suite)

for case in keys(result["signal"])
    m1 = minimum(result["signal"][case])
    m2 = minimum(result["baseline"][case])
    println("")
    println("Ratio to bare julia for $case: ")
    println("----------------------------------------")
    display(ratio(m1,m2))
end