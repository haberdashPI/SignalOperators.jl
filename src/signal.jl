export duration, nsamples, samplerate, nchannels, signal, sink, sink!
using AxisArrays
using FileIO

# Signals have a sample rate and some iterator element type
# T, which is an NTuple{N,<:Number}.
struct IsSignal{T,Fs,L}
end
SignalTrait(x::T) where T = SignalTrait(T)
SignalTrait(::Type{T}) where T = nothing
IsSignal{T}(fs::Fs,len::L) where {T,Fs,L} = IsSignal{T,Fs,L}()

function show_fs(io,x)
    if !get(io,:compact,false) && !ismissing(samplerate(x))
        write(io," (")
        show(io, MIME("text/plain"), samplerate(x))
        write(io," Hz)")
    end
end
signalshow(io,x) = show(io,MIME("text/plain"),x)
function tilepipe(child,operate)
    single = child * literal(" |> ") * operate
    breaking = child * literal(" |>") / indent(4) * operate
    single | breaking
end

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

"""

    samplerate(x)

Returns the sample rate of the signal (in Hertz). May return `missing` if the 
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

Coerce `x` to be a signal, optionally specifying its sample rate (usually in
Hz). All signal operators first call `signal(x)` for each argument. This
means you only need to call `signal` when you want to pass additional
arguments to it.

!!! note

    If you pipe `signal` (e.g. `myobject |> signal(2kHz)`) you must specify
    the units of the sample rate, if passed. A unitless number is always
    interpreted as a constant, infinite-length signal (see below).

The types of objects that can be coerced to signals are as follows.
"""
signal(;kwds...) = x -> signal(x;kwds...)
signal(fs::Quantity;kwds...) = x -> signal(x,fs;kwds...)
signal(x,fs::Union{Number,Missing}=missing) = signal(x,SignalTrait(x),fs)
signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")

"""

## Existing signals

Any existing signal just returns itself from `signal`. If a sample rate is
specified it will be set if `x` has an unknown sample rate. If it has a known
sample rate and doesn't match `samplerate(x)` an error will be thrown. If
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

# computed signals have to implement there own version of tosamplerate
# (e.g. resample) to avoid inefficient computations

struct DataSignal
end
struct ComputedSignal
end
EvalTrait(x) = DataSignal()
EvalTrait(x::AbstractSignal) = ComputedSignal()
