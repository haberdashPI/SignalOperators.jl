export duration, nsamples, samplerate, samples, nchannels, signal
using MetaArrays
using FileIO

# Signals have a sample rate
struct IsSignal{T}
    samplerate::Float64
end
SignalTrait(x) = nothing

# not everything that's a signal belongs to this package, (hence the use of
# trait-based dispatch), but everything that is in this package is a child of
# `AbstractSignal`. This allows for easy dispatch to convert such signals to
# another object type (e.g. Array or AxisArray)
abstract type AbstractSignal
end

# TODO: change of definitions
# just use length(samples(x)) to define all three of these
# (change all other definitions of these functions throughout)

duration(x) = nsamples(x) / samplerate(x)
nsamples(x) = length(samples(x))

infsigal(x) = infsigal(x,SignalTrait(x))
infsignal(x,s::IsSignal) = infsignal(x,s,Iterators.IteratorSize(samples(x)))
infsignal(x,::IsSignal,::Iterators.HasLength) = false
infsignal(x,::IsSignal,::Iterators.IsInfinite) = true
infsignal(x,::Nothing) = error("Value is not a signal: $x")

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,::Nothing) = error("Value is not a signal: $x")

checksamplerate(fs,_fs) = isnothing(fs) || _fs == fs

samples(x) = samples(x,SignalTrait(x))
samples(x,::IsSignal) = x
samples(x,::Nothing) = error("value is not a signal: $x")

nchannels(x) = nchannels(x,SignalTrait(x))
nchannels(x,::IsSignal{NTuple{N}}) where N = N
nchannels(x,::Nothing) = error("value is not a signal: $x")

signal_eltype(x) = signal_eltype(x,SignalTrait(x))
signal_eltype(x,::IsSignal{NTuple{<:Any,T}}) where T = T
signal_eltype(x,::Nothing) = error("value is not a signal: $x")

signal(x,fs) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")
function signal(x,::IsSignal,fs)
    checksamplerate(fs,samplerate(x))
    x
end