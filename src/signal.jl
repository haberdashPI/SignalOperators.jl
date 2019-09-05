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
    if ismissing(samplerate(x))
        tosamplerate(x,fs)
    elseif !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
    else
        x
    end
end

"""
    sink([signal],[to=Array];length,samplerate)

Creates a given type of object from a signal. By default it is an `AxisArray`
with time as the rows and channels as the columns. If a filename is specified
for `to`, the signal is written to the given file. If given a type (e.g.
`Array`) the signal is written to that type. The samplerate does not
need to be specified unless `samplerate(signal)` is a missing value.

If the signal is not specified, creates a single argument function which,
when called, sends the given signal to the sink. (e.g. `mysignal |>
sink("result.wav")`)

"""
sink(to;kwds...) = x -> sink(x,to;kwds...)
function sink(x::T,::Type{A}=AxisArray;
        length=nsamples(x)*frames,
        samplerate=samplerate(x)) where {T,A}

    x = signal(x,samplerate)
    sink(x,SignalTrait(T),inframes(Int,length,samplerate(x)),A)
end
sink_init(sig) = Array{channel_eltype(sig)}(undef,nsamples(sig),nchannels(sig))
function sink!(result::Union{AbstractVector,AbstractMatrix},x;offset=0,
    samplerate=SignalOperators.samplerate(x)) 
    x = signal(x,samplerate)

    if nsamples(x)-offset < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = tochannels(x,size(result,2))

    sink!(result,x,SignalTrait(x),offset)
end

abstract type AbstractCheckpoint
end
isless(x::AbstractCheckpoint,y::AbstractCheckpoint) = isless(checkindex(x),checkindex(y))
checkpoints(x,offset,len) = [EmptyCheckpoint(1),EmptyCheckpoint(len+1)]
struct EmptyCheckpoint
    n::Int
end
checkindex(x::EmptyCheckpoint) = x.n

sampleat!(result,x,s::IsSignal,i::Number,j::Number,check) = 
    sampleat!(result,x,s,i,j)
fold(x) = zip(x,Iterators.drop(x,1))
function sink!(result,x,sig::IsSignal,offset::Number)
    checks = checkpoints(x,offset,size(result,1))
    for (check,next) in fold(checkpoints)
        sinkchunk!(result,x,sig,offset,check,checkindex(next)-1)
    end
end
function sinkchunk!(result,x,sig,offset,check,last)
    @simd @inbounds for i in checkindex(check):last
        sampleat!(result,x,sig,i-offset,i,check)
    end
end

# New idea: rather than having blocks, have "checkpoints"
# a signal can define check points, which will be used to perform
# intermediate oeprations: all sinks must implement sampleat!
# and can optionally implement sink_checkpoints oncheckpoint, and

function sink(x,sig::IsSignal,::Nothing,T)
    error("Cannot store infinite signal in an array.",
           " Specify a length when calling `sink`.")
end
function sink(x,sig::IsSignal{El},len::Number,::Type{<:Array}) where El
    result = Array{El}(undef,len,nchannels(x))
    sink!(result,x,sig)
end
function sink(x,sig::IsSignal{El},len,::Type{<:AxisArray}) where El
    result = sink(x,sig,len,Array)
    times = Axis{:time}(range(0s,length=size(result,1),step=s/samplerate(x)))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(result,times,channels)
end
sink(x, ::IsSignal, ::Nothing, ::Type) = error("Don't know how to interpret value as a signal: $x")
writesink(result::AbstractArray,i,val) = result[i,:] .= val

# TODO: we need just one function
# signal_setindex!(result,ri,x,xi)
#
# I have already defined the basic idea here and there throughout the
# code base. But I am just missing the ri, which needs to change differently
# from xi (instead of using a signle index)

# this still needs a little rethinking: how do I deal with interacting
# blocks, and how do I deal with the fact that I want some children
# to use a block and some to use signle indices
# theres' probably a simpler solution

Base.zero(x::AbstractSignal) = signal(zero(channel_eltype(x)),samplerate(x))
Base.one(x::AbstractSignal) = signal(one(channel_eltype(x)),samplerate(x))