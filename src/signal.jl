export duration, nsamples, samplerate, nchannels, signal
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
# MAYBE checkpoints, beforecheckpoint and aftercheckpoint

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

struct InfiniteLength
end
const inflen = InfiniteLength()
Base.isinf(::InfiniteLength) = true
isinf(x) = Base.isinf(x)
# for our purposes, missing values always denote an unknown finite value
isinf(::Missing) = false
Base.ismissing(::InfiniteLength) = false
Base.:(+)(::InfiniteLength,::Number) = inflen
Base.:(+)(::Number,::InfiniteLength) = inflen
Base.:(-)(::InfiniteLength,::Number) = inflen
Base.isless(::Number,::InfiniteLength) = true
Base.isless(::InfiniteLength,::Number) = false
Base.isless(::InfiniteLength,::InfiniteLength) = false
Base.min(x::Number,::InfiniteLength) = x
Base.min(::InfiniteLength,x::Number) = x
Base.max(x::Number,::InfiniteLength) = inflen
Base.max(::InfiniteLength,x::Number) = inflen
Base.:(*)(::InfiniteLength,::Number) = inflen
Base.:(*)(::Number,::InfiniteLength) = inflen
Base.:(*)(::InfiniteLength,::Unitful.FreeUnits) = inflen
Base.:(/)(::InfiniteLength,::Number) = inflen
Base.:(/)(::InfiniteLength,::Missing) = inflen
Base.:(/)(::Number,::InfiniteLength) = 0

samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,::Nothing) = nosignal(x)

nchannels(x) = nchannels(x,SignalTrait(x))
nchannels(x,::Nothing) = nosignal(x)

channel_eltype(x) = channel_eltype(x,SignalTrait(x))
channel_eltype(x,::IsSignal{T}) where T = T

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
sink(to::Type=AxisArray;kwds...) = x -> sink(x,to;kwds...)
function sink(x::T,::Type{A}=AxisArray;
        length=missing,
        samplerate=SignalOperators.samplerate(x)) where {T,A}

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)
    length = coalesce(length,nsamples(x))

    if isinf(length)
        error("Cannot store infinite signal. Specify a length when ",
            "calling `sink`.")
    end

    sink(x,SignalTrait(T),inframes(Int,maybeseconds(length),
        SignalOperators.samplerate(x)),A)
end

function sink(x,sig::IsSignal{El},len::Number,::Type{<:Array}) where El
    result = Array{El}(undef,len,nchannels(x))
    sink!(result,x)
end
function sink(x,sig::IsSignal{El},len,::Type{<:AxisArray}) where El
    result = sink(x,sig,len,Array)
    times = Axis{:time}(range(0s,length=size(result,1),step=float(s/samplerate(x))))
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

    if nsamples(x)-offset < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = tochannels(x,size(result,2))

    sink!(result,x,SignalTrait(x),offset)
end

abstract type AbstractCheckpoint
end
struct EmptyCheckpoint <: AbstractCheckpoint
    n::Int
end
checkindex(x::EmptyCheckpoint) = x.n

checkpoints(x,offset,len) = 
    [EmptyCheckpoint(offset+1),EmptyCheckpoint(offset+len+1)]
beforecheckpoint(x,check,len) = nothing
aftercheckpoint(x,check,len) = nothing

# sampleat!(result,x,sig,i,j,check) = sampleat!(result,x,sig,i,j)

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal,offset::Number) = 
    sink!(result,x,sig,checkpoints(x,offset,size(result,1)))
function sink!(result,x,sig::IsSignal,checks::AbstractArray)
    n = 1-checkindex(checks[1])
    for (check,next) in fold(checks)
        len = checkindex(next) - checkindex(check)
        beforecheckpoint(x,check,len)
        sink_helper!(result,n,x,sig,check,len)
        aftercheckpoint(x,check,len)
    end
    result
end

function sink_helper!(result,n,x,sig,check,len)
    if len > 0
        @inbounds @simd for i in checkindex(check):(checkindex(check)+len-1)
            sampleat!(result,x,sig,n+i,i,check)
        end
    end
end
function writesink(result::AbstractArray,i,v)
    result[i,:] .= v
end

# computed signals have to implement there own version of tosamplerate
# (e.g. resample) to avoid inefficient computations

struct DataSignal
end
struct ComputedSignal
end
EvalTrait(x) = DataSignal()
EvalTrait(x::AbstractSignal) = ComputedSignal()
