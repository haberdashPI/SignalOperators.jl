export duration, nsamples, samplerate, samples, nchannels, signal, infsignal
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

duration(x) = nsamples(x) / samplerate(x)
nsamples(x) = length(samples(x))

infsignal(x) = infsignal(x,SignalTrait(x))
infsignal(x,s::IsSignal) = infsignal(x,s,Iterators.IteratorSize(samples(x)))
infsignal(x,::IsSignal,::Iterators.HasLength) = false
infsignal(x,::IsSignal,::Iterators.HasShape) = false
infsignal(x,::IsSignal,::Iterators.IsInfinite) = true
infsignal(x,::Nothing) = error("Value is not a signal: $x")

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,s::IsSignal) = s.samplerate
samplerate(x,::Nothing) = error("Value is not a signal: $x")

checksamplerate(fs,_fs) = ismissing(fs) || _fs == inHz(fs)

samples(x) = samples(x,SignalTrait(x))
samples(x::AbstractSignal,::IsSignal) = x
samples(x,::Nothing) = error("value is not a signal: $x")

nchannels(x) = nchannels(x,SignalTrait(x))
nchannels(x,::IsSignal{<:NTuple{N}}) where N = N
nchannels(x,::Nothing) = error("value is not a signal: $x")

channel_eltype(x::T) where T = channel_eltype(T)
channel_eltype(::Type{T}) where T = ntuple_T(signal_eltype(T))
ntuple_T(::Type{<:NTuple{<:Any,T}}) where T = T

signal_eltype(::Type{T}) where T <: AbstractSignal = eltype(T)
signal_eltype(::T) where T = signal_eltype(T)

signal(fs::Quantity) = x -> signal(x,fs)
signal(x,fs) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")
function signal(x,::IsSignal,fs)
    if !checksamplerate(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
    end
    x
end