using BenchmarkTools
using SignalOperators
using SignalOperators.Units
using Random
using Statistics
using DSP

suite = BenchmarkGroup()
suite["signal"] = BenchmarkGroup()
suite["baseline"] = BenchmarkGroup()

rng = MersenneTwister(1983)
x = rand(rng,10^4,2)
y = rand(rng,10^4,2)

suite["signal"]["sinking"] = @benchmarkable signal(x,1000Hz) |> sink
suite["baseline"]["sinking"] = @benchmarkable copy(x)
suite["signal"]["functions"] = @benchmarkable begin
    signal(sin,ω=10Hz) |> sink(length=10^4,samplerate=1000Hz)
end
suite["signal"]["baseline"] = @benchmarkable begin
    sin.(range(0,step=1/1000,length=10^4) .* (2π*10))
end
suite["signal"]["cutting"] = @benchmarkable x |> until(5*10^4*samples) |> sink(samplerate=1000Hz)
suite["baseline"]["cutting"] = @benchmarkable x[1:(5*10^4)]
suite["signal"]["mapping"] = @benchmarkable sink(mix($x,$y),samplerate=1000Hz)
suite["baseline"]["mapping"] = @benchmarkable $x .+ $y
suite["signal"]["appending"] = @benchmarkable sink(append($x,$y),samplerate=1000Hz)
suite["baseline"]["appending"] = @benchmarkable vcat($x,$y)
suite["signal"]["padding"] = @benchmarkable begin
    pad($x,zero) |> until(2_000samples) |> sink(samplerate=1000Hz)
end
suite["baseline"]["padding"] = @benchmarkable vcat($x,zeros($x))
suite["signal"]["filtering"] = @benchmarkable begin
    lowpass($x,20Hz) |> sink(samplerate=1000Hz)
end
suite["signal"]["filtering"] = @benchmarkable begin
    filt(digitalfilter(Lowpass(20,Fs=1000),Butterworth(5)),$x)
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
    m1 = median(result["signal"][case])
    m2 = median(result["baseline"][case])
    println("")
    println("Results for $case: ")
    println("----------------------------------------")
    display(ratio(m1,m2))
end