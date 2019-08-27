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

duration(x) = duration(x,SignalTrait(x))
duration(x,s::IsSignal) = inseconds(signal_length(x,s),samplerate(x))
duration(x,::Nothing) = error("Value is not a signal: $x")

nsamples(x) = nsamples(x,SignalTrait(x))
nsamples(x,s::IsSignal) = inframes(Int,signal_length(x,s),samplerate(x))+1
nsamples(x,::Nothing) = error("Value is not a signal: $x")

signal_length(x) = signal_length(x,SignalTrait(x))
signal_length(x,::IsSignal) = infinite_length
signal_length(x,::Nothing) = error("Value is not a signal: $x")

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,s::IsSignal) = s.samplerate
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

struct NumberSignal{T}
    val::T
    samplerate::Float64
end
signal(val::Number,fs) = NumberSignal(val,Float64(inHz(fs)))
SignalTrait(x::NumberSignal) = IsSignal(x.samplerate)
struct Blank
end
const blank = Blank()
Base.iterate(x::NumberSignal,state=blank) = (x,),state
Base.IteratorEltype(x::NumberSignal) = HasEltype()
Base.eltype(x::NumberSignal{T}) where T = T
Base.IteratorSize(::Type{<:NumberSignal}) = IsInfinite()

signal_eltype(x) = ntuple_T(eltype(samples(x)))
ntuple_T(x::NTuple{<:Any,T}) where T = T