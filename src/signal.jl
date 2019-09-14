export duration, nsamples, samplerate, nchannels, signal, sink, sink!, inflen
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

"""

    duration(x)

Return the duration of the signal in seconds, if known. May
return `missing` or [`inflen`](@ref). The value `missing` always denotes a finite,
but unknown length.

"""
duration(x) = nsamples(x) / samplerate(x)
"""

    nsamples(x)

Returns the number of samples in the signal, if known. May
return `missing` or [`inflen`](@ref). The value `missing` always denotes a finite,
but unknown length.

"""
nsamples(x) = nsamples(x,SignalTrait(x))
nsamples(x,s::Nothing) = nosignal(x)

struct InfiniteLength
end

@doc """

    inflen

Represents an infinite length. Proper overloads are defined to handle 
arithematic and ordering for the infinite value.

"""
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

"""

    samplerate(x)

Returns the sample rate of the signal (in Hz). May return `missing` if the 
sample rate is unknown.

"""
samplerate(x) = samplerate(x,SignalTrait(x))
samplerate(x,::Nothing) = nosignal(x)

"""

    nchannels(x)

Returns the number of channels in the signal.

"""
nchannels(x) = nchannels(x,SignalTrait(x))
nchannels(x,::Nothing) = nosignal(x)

"""

    channel_eltype(x)

Returns the element type of an individual channel of a signal (e.g. `Float64`).

!!! note

    `channel_eltype` and `eltype` are, in most cases, the same, but
    not necesarilly so.

"""
channel_eltype(x) = channel_eltype(x,SignalTrait(x))
channel_eltype(x,::IsSignal{T}) where T = T

isconsistent(fs,_fs) = ismissing(fs) || inHz(_fs) == inHz(fs)

"""
    signal(x,[samplerate])

Coerce `x` to be a signal, optionally specifying its sample rate (usually in Hz).
Signal operations first coerce their arguments to be a signal so this needs
only to be specified when the additional arguments to signal are needed.

!!! note

    If you pipe `signal` (e.g. `myobject |> signal(2kHz)`) you must specify
    the units of the sample rate. This is because a raw number is ambiguous,
    and could be interpreted as a signal (i.e. an infinite length signal of
    with constant valued samples).

The types of objects that can be coerced to signals are as follows.
"""
signal(fs::Quantity) = x -> signal(x,fs)
signal(x,fs::Union{Number,Missing}=missing) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")

"""

## Existing signals

Any existing signal just returns itself from `signal`. If a sample rate is
specified it will be set if `x` has an unknown sample rate. If it has a known
sample rate and doesn't match `samplerate(x)` and error will be throwns. If
you want to change the sample rate of a signal use [`tosamplerate`](@ref).

"""
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
    sink([signal],[to=AxisArray];length,samplerate)

Creates a given type of object (`to`) from a signal. By default it is an
`AxisArray` with time as the rows and channels as the columns. If a filename
is specified for `to`, the signal is written to the given file. If given a
type (e.g. `Array`) the signal is written to that type. The sample rate does
not need to be specified, it will use either the sample rate of `signal` or a
default sample rate (which raises a warning). 

You can specify a length or samplerate for the signal when calling sink if it
has yet to be defined.

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
    length = coalesce(length,nsamples(x)*samples)

    if isinf(length)
        error("Cannot store infinite signal. Specify a length when ",
            "calling `sink`.")
    end

    sink(x,SignalTrait(T),insamples(Int,maybeseconds(length),
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

"""
    sink!(array,x;[samplerate],[offset])

Write samples of the signal `x` to `array`, starting from the sample after
`offset`. If no sample rate has been specified for `x` you can specify it
now, using `samplerate` (it will default to 44.1kHz).

"""
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
