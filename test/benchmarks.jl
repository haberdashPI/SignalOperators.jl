

using BenchmarkTools
using SignalOperators
using SignalOperators.Units
using Random
using Traceur
using Statistics
using DSP

dB = SignalOperators.Units.dB

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

# TODO: there still seems to be some per O(N) growth
# in the # of allocs... is that just the call to `filter`?
suite["signal"]["overall"] = @benchmarkable begin
    N = 10000
    x_ = rand(2N,2)
    mix(signal(sin,ω=10Hz),x_) |>
        tosamplerate(2000Hz) |>
        until(0.5*N*samples) |> after(0.25*N*samples) |>
        append(sin) |> until(N*samples) |>
        lowpass(20Hz) |>
        normpower |> amplify(-10dB) |>
        sink
end

suite["baseline"]["overall"] = @benchmarkable begin
    N = 10000
    x_ = rand(2N,2)
    y = sin.(2π.*10.0.*range(0,0.5,length=N))
    y = hcat(y,y)
    z = sin.(range(0,0.5,length=N))
    app = vcat(x_[1:N,:] .+ y,hcat(z,z))
    f = filt(digitalfilter(Lowpass(20,fs=2000),Butterworth(5)),app)
    f ./= 2sqrt(mean(f.^2))
    f
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
    println("$case: ratio to bare julia")
    println("----------------------------------------")
    display(ratio(m1,m2))
end