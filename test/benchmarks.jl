

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
x = rand(rng,10^1,2)
y = rand(rng,10^1,2)
# x = rand(rng,10^4,2)
# y = rand(rng,10^4,2)

suite["signal"]["sinking"] = @benchmarkable signal(x,1000Hz) |> sink
suite["baseline"]["sinking"] = @benchmarkable copy(x)
suite["signal"]["functions"] = @benchmarkable begin
    signal(sin,ω=10Hz) |> sink(length=10^4*samples,samplerate=1000Hz)
end
suite["baseline"]["functions"] = @benchmarkable begin
    sinpi.(range(0,step=1/1000,length=10^4) .* (2*10))
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

# TODO: mapsignal is still allocating during `sink!`: what's happening
# is that the broadcast operation over `+` is creating a small array;
# We need to 
#
# 1. handle bychannel=true and bychannel=false separately
# 2. make sure the oepration simplifies down to a loop across
#    the channels for bychannel=true
# 3. make sure the input to fn for bychannel=false is a inferrable tuple so
#    that operations wihtin fn are easy to implement with stack-only operations

suite["signal"]["mapping"] = @benchmarkable sink(mix($x,$y),samplerate=1000Hz)
suite["baseline"]["mapping"] = @benchmarkable $x .+ $y
# suite["signal"]["filtering"] = @benchmarkable begin
#     lowpass($x,20Hz) |> sink(samplerate=1000Hz)
# end
# suite["signal"]["filtering"] = @benchmarkable begin
#     filt(digitalfilter(Lowpass(20,Fs=1000),Butterworth(5)),$x)
# end

# paramspath = joinpath(@__DIR__,"params.json")

# if isfile(paramspath)
#     loadparams!(suite, BenchmarkTools.load(paramspath)[1], :evals)
# else
#     tune!(suite)
#     BenchmarkTools.save(paramspath, params(suite))
# end

result = run(suite)

for case in keys(result["signal"])
    m1 = median(result["signal"][case])
    m2 = median(result["baseline"][case])
    println("")
    println("Results for $case: ")
    println("----------------------------------------")
    display(ratio(m1,m2))
end