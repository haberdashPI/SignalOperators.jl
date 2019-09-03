export duration, nsamples, samplerate, samples, nchannels, signal, infsignal
using MetaArrays
using FileIO

# Signals have a sample rate and some iterator element type
# T, which is an NTuple{N,<:Number}.
struct IsSignal{T,Fs,L}
end
SignalTrait(x::T) where T = SignalTrait(T)
SignalTrait(::Type{T}) where T = nothing
IsSignal{T}(fs::Fs,len::L) where {T,Fs,L} = IsSignal{T,Fs,L}()

# signals must implement
# SignalTrait(x) for x as a value or a type
# nchannels(x) (may return nothing)
# nsamples(x)
# samplerate(x)
# samples(x) (an iterator of samples)

# not everything that's a signal belongs to this package, (hence the use of
# trait-based dispatch), but everything that is in this package is a child of
# `AbstractSignal`. This allows for easy dispatch to convert such signals to
# another object type (e.g. Array or AxisArray)
abstract type AbstractSignal{T}
end

nosignal(x) = error("Value is not a signal: $x")

duration(x) = nsamples(x) / samplerate(x)
nsamples(x) = nsamples(x,SignalTrait(x))
nsamples(x,s::Nothing) = nosignal(x)

infsignal(x) = infsignal(x,SignalTrait(x))
infsignal(x,::IsSignal{<:Any,<:Any,<:Number}) = false
infsignal(x,::IsSignal{<:Any,<:Any,Nothing}) = true
infsignal(x,::Nothing) = nosignal(x)

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,::Nothing) = nosignal(x)

samples(x) = samples(x,SignalTrait(x))
samples(x::AbstractSignal,::IsSignal) = x
samples(x,::Nothing) = nosignal(x)

nchannels(x) = nchannels(x,SignalTrait(x))
nchannels(x,::Nothing) = nosignal(x)

channel_eltype(x) = channel_eltype(x,SignalTrait(x))
channel_eltype(x,::IsSignal{T}) where T = T
Base.Iterators.IteratorSize(::Type{T}) where T <: AbstractSignal =
    Iterators.IteratorSize(SignalTrait(T))
Base.Iterators.IteratorSize(x::Type{S}) where 
    {T,Fs,S <: IsSignal{T,Fs,<:Nothing}} = Iterators.IsInfinite
Base.Iterators.IteratorSize(x::Type{S}) where 
    {T,Fs,S <: IsSignal{T,Fs,<:Number}} = Iterators.HasLength

isconsistent(fs,_fs) = ismissing(fs) || inHz(_fs) == inHz(fs)

signal(fs::Quantity) = x -> signal(x,fs)
signal(x,fs::Union{Number,Missing}=missing) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")
function signal(x,::IsSignal,fs)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
    end
    x
end

"""
    sink([to=Array])
    sink(signal,[to=Array])

Creates a given type of object from a signal. By default it is an `AxisArray` with
time as the rows and channels as the columns. If a filename is specified, the
signal is written to the given file. If given a type (e.g. `Array`) the
signal is written to that type. 

If no signal is given, creates a single argument function which, when called,
sends the given signal to the sink. (e.g. `mysignal |> sink("result.wav")`)

"""
sink(::Type{T}=AxisArray) where T = x -> sink(x,T)
sink(x,::Type{T}=AxisArray) where T = sink(x,SignalTrait(x),T)

sink_init(sig) = Array{channel_eltype(sig)}(undef,nsamples(sig),nchannels(sig))

function sink(x,sig::IsSignal)
function sink(x,sig::IsSignal{El},::Type{<:Array}) where El
    smp = samples(x)
    sink(x,sig,smp,Iterators.IteratorSize(smp))
end
function sink(x,sig::IsSignal{El},::Type{<:AxisArray}) where El
    result = sink(x,sig,Array)
    times = Axis{:time}(range(0s,length=size(result,1),step=s/samplerate(x)))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(result,times,channels)
end
sink(x, ::Nothing, ::Type) = error("Don't know how to interpret value as a signal: $x")

function sink(xs,::IsSignal,smp,::Iterators.HasLength)
    result = sink_init(xs)
    samples_to_result!(result,smp)
end
function samples_to_result!(result,smp)
    for (i,x) in enumerate(smp)
        result[i,:] .= x
    end
    result
end
function sink(x,::IsSignal,smp,::Iterators.IsInfinite)
    error("Cannot store infinite signal in an array. (Use `until`?)")
end

Base.zero(x::AbstractSignal) = signal(zero(channel_eltype(x)),samplerate(x))
Base.one(x::AbstractSignal) = signal(one(channel_eltype(x)),samplerate(x))