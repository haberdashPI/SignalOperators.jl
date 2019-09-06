export duration, nsamples, samplerate, samples, nchannels, signal, infsignal
using AxisArrays
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
# sampleat! 
# MAYBE sinkchunk! and/or checkpoints

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

Creates a given type of object (`to`) from a signal. By default it is an
`AxisArray` with time as the rows and channels as the columns. If a filename
is specified for `to`, the signal is written to the given file. If given a
type (e.g. `Array`) the signal is written to that type. The sample rate does
not need to be specified, it will use either the sample rate of `signal` or a
default sample rate (which raises a warning). 

You can specify a length for the signal, in seconds or frames. If the value
is a unitless number, it is assumed to be the number of frames (and will be
rounded as necessary). 

If the signal is not specified, this creates a single argument function which,
when called, sends the passed signal to the sink. (e.g. `mysignal |>
sink("result.wav")`)

"""
sink(to;kwds...) = x -> sink(x,to;kwds...)
function sink(x::T,::Type{A}=AxisArray;
        length=infsignal(x) ? nothing : nsamples(x)*frames,
        samplerate=SignalOperators.samplerate(x)) where {T,A}

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)

    sink(x,SignalTrait(T),inframes(Int,length,SignalOperators.samplerate(x)),A)
end

function sink(x,sig::IsSignal,::Nothing,T)
    error("Cannot store infinite signal. Specify a length when calling `sink`.")
end
function sink(x,sig::IsSignal{El},len::Number,::Type{<:Array}) where El
    result = Array{El}(undef,len,nchannels(x))
    sink!(result,x)
end
function sink(x,sig::IsSignal{El},len,::Type{<:AxisArray}) where El
    result = sink(x,sig,len,Array)
    times = Axis{:time}(range(0s,length=size(result,1),step=s/samplerate(x)))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(result,times,channels)
end
sink(x, ::IsSignal, ::Nothing, ::Type) = error("Don't know how to interpret value as a signal: $x")

function sink!(result::Union{AbstractVector,AbstractMatrix},x;
    samplerate=SignalOperators.samplerate(x),offset=0) 

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)

    if !infsignal(x) && nsamples(x)-offset < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = tochannels(x,size(result,2))

    sink!(result,x,SignalTrait(x),offset)
end

abstract type AbstractCheckpoint
end
struct EmptyCheckpoint
    n::Int
end
checkindex(x::EmptyCheckpoint) = x.n

checkpoints(x,offset,len) = [EmptyCheckpoint(1),EmptyCheckpoint(len+1)]
checkpoints(x,offset,len,saved_state) = checkpoints(x,offset,len)

sampleat!(result,x,s::IsSignal,i::Number,j::Number,check) = 
    sampleat!(result,x,s,i,j)
fold(x) = zip(x,Iterators.drop(x,1))
function sink!(result,x,sig::IsSignal,offset::Number)
    checks = checkpoints(x,offset,size(result,1))
    n = 0
    for (check,next) in fold(checkpoints)
        sinkchunk!(result,n-checkindex(next),x,sig,check,checkindex(next)-1)
        n += checkindex(check)
    end
    result
end
function sinkchunk!(result,off,x,sig,check,until)
    @inbounds @simd for i in checkindex(check):until
        sampleat!(result,x,sig,i+off,i)
    end
end
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