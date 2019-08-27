export duration, nsamples, samplerate, samples, nchannels, signal
using MetaArrays
using FileIO

struct InfiniteLength
end
Base.isinf(::InfiniteLength) = true
const infinite_length = InfiniteLength()
Base.:(+)(::InfiniteLength,::Number) = infinite_length
Base.:(+)(::Number,::InfiniteLength) = infinite_length
Base.:(-)(::InfiniteLength,::Number) = infinite_length
Base.:(-)(::Number,::InfiniteLength) = infinite_length
Base.min(x::Number,::InfiniteLength) = x
Base.min(::InfiniteLength,x::Number) = x
Base.max(x::Number,::InfiniteLength) = infinite_length
Base.max(::InfiniteLength,x::Number) = infinite_length
Base.:(*)(::InfiniteLength,::Number) = infinite_length
Base.:(*)(::InfiniteLength,::Unitful.FreeUnits) = infinite_length

# Signals have a sample rate
struct IsSignal
    samplerate::Float64
end
SignalTrait(x) = nothing

# TODO: change of definitions
# just use length(samples(x)) to define all three of these
# (change all other definitions of these functions throughout)

duration(x) = nsamples(x) / samplerate(x)
nsamples(x) = length(samples(x))

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,::Nothing) = error("Value is not a signal: $x")

checksamplerate(fs,_fs) = isnothing(fs) || _fs == fs

samples(x) = samples(x,SignalTrait(x))
samples(x,::IsSignal) = x
samples(x,::Nothing) = error("value is not a signal: $x")

nchannels(x) = ntuple_N(eltype(samples(x)))
ntuple_N(::Type{<:NTuple{N}}) where N = N

signal(x,fs) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")
function signal(x,::IsSignal,fs)
    checksamplerate(fs,samplerate(x))
    x
end