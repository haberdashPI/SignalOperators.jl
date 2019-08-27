using MetaArrays
using FileIO

struct InfiniteLength
end
Base.isinf(::InfiniteLength) = true
const infinite_length = InfiniteLength()

# Signals have a sample rate
struct IsSignal
    samplerate::Float64
end
SignalTrait(x) = nothing

duration(x) = duration(x,SignalTrait(x))
duration(x,s::IsSignal) = inseconds(signal_length(x),samplerate(x))
duration(x,::Nothing) = error("Value is not a signal: $x")

nsamples(x) = nsamples(x,SignalTrait(x))
nsamples(x,::SignalTrait) = inframes(Int,signal_length(x),samplerate(x))+1
nsamples(x,::Nothing) = error("Value is not a signal: $x")

signal_length(x) = signal_length(x,SignalTrait(x))
signal_length(x,::SignalTrait) = infinite_length
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
signal(x::Number,fs) = NumberSignal(val,fs)
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