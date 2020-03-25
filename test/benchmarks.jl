using BenchmarkTools
using SignalOperators
using SignalOperators.Units
using Random
using Traceur
using Statistics
using DSP

# TODO: slow performance for my german_track project
# TODO: test randn on its own
# TODO: test randn combined with filter

dB = SignalOperators.Units.dB

suite = BenchmarkGroup()
suite["signal"] = BenchmarkGroup()
suite["baseline"] = BenchmarkGroup()

rng = MersenneTwister(1983)
# x = rand(rng,10^1,2)
# y = rand(rng,10^1,2)
x = rand(rng,10^4,2)
y = rand(rng,10^4,2)

Signal(x,1000Hz) |> ToFramerate(500Hz) |> sink

suite["signal"]["sinking"] = @benchmarkable Signal(x,1000Hz) |> sink
suite["baseline"]["sinking"] = @benchmarkable copy(x)
suite["signal"]["functions"] = @benchmarkable begin
    Signal(sin,ω=10Hz) |> Until(10kframes) |> ToFramerate(1000Hz) |> sink
end
suite["baseline"]["functions"] = @benchmarkable begin
    sinpi.(range(0,step=1/1000,length=10^4) .* (2*10))
end
suite["signal"]["numbers"] = @benchmarkable begin
    1 |> Until(10_000frames) |> ToFramerate(1000Hz) |> sink
end
suite["baseline"]["numbers"] = @benchmarkable begin
    ones(10_000)
end

suite["signal"]["cutting"] = @benchmarkable begin
    x |> Until(5*10^3*frames) |> ToFramerate(1000Hz) |> sink
end
suite["baseline"]["cutting"] = @benchmarkable x[1:(5*10^3)]
suite["signal"]["padding"] = @benchmarkable begin
    Pad($x,zero) |> Until(20_000frames) |> ToFramerate(1000Hz) |> sink
end
suite["baseline"]["padding"] = @benchmarkable vcat($x,zero($x))
suite["signal"]["appending"] = @benchmarkable sink(ToFramerate(Append($x,$y),1000Hz))
suite["baseline"]["appending"] = @benchmarkable vcat($x,$y)

suite["signal"]["mapping"] = @benchmarkable sink(ToFramerate(Mix($x,$y),1000Hz))
suite["baseline"]["mapping"] = @benchmarkable $x .+ $y

suite["signal"]["filtering"] = @benchmarkable begin
    Filt($x,Lowpass,20Hz) |> ToFramerate(1000Hz) |> sink
end
suite["baseline"]["filtering"] = @benchmarkable begin
    Filt($x,digitalfilter(Lowpass(20,fs=1000),Butterworth(5))) |>
        ToFramerate(1000Hz) |> sink
end

suite["signal"]["resampling"]  = @benchmarkable begin
    Signal($x,1000Hz) |> ToFramerate(500Hz) |> sink
end
suite["baseline"]["resampling"]  = @benchmarkable begin
    Filters.resample($(x[:,1]),1//2)
    Filters.resample($(x[:,2]),1//2)
end

suite["signal"]["resampling-irrational"]  = @benchmarkable begin
    Signal($x,1000Hz) |> ToFramerate(π*1000Hz) |> sink
end
suite["baseline"]["resampling-irrational"]  = @benchmarkable begin
    Filters.resample($(x[:,1]),Float64(π))
    Filters.resample($(x[:,2]),Float64(π))
end


# TODO: there still seems to be some per O(N) growth
# in the # of allocs... is that just the call to `filter`?
suite["signal"]["overall"] = @benchmarkable begin
    N = 10000
    x_ = rand(2N,2)
    Mix(Signal(sin,ω=10Hz),x_) |>
        ToFramerate(2000Hz) |>
        Until(0.5*N*frames) |> After(0.25*N*frames) |>
        Append(sin) |> Until(N*frames) |>
        Filt(Lowpass,20Hz) |>
        Normpower |> Amplify(-10dB) |>
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