export duration, nsamples, samplerate, nchannels, signal, sink, sink!, channel_eltype
using AxisArrays
using FileIO

# Signals have a sample rate and some iterator element type
# T, which is an NTuple{N,<:Number}.
"""
    SignalOperators.IsSignal{T,Fs,L}

Represents the format of a signal type with three type parameters:

* `T` - The [`channel_eltype`](@ref) of the signal.
* `Fs` - The type of the samplerate. It should be either `Float64` or
    `Missing`.
* `L` - The type of the length of the signal. It should be either
`InfiniteLength`, `Missing` or `Int`.

"""
struct IsSignal{T,Fs,L}
end

"""

    SiganlOperators.SignalTrait(::Type{T}) where T

Returns either `nothing` if the type T should not be considered a signal (the
default) or [`IsSignal`](@ref) to indicate the signal format for this signal.

"""
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

# not everything that's a signal belongs to this package, (hence the use of
# trait-based dispatch), but everything that is in this package is a child of
# `AbstractSignal`. This allows for easy dispatch to convert such signals to
# another object type (e.g. Array or AxisArray)
abstract type AbstractSignal{T}
end

indexable(x::AbstractArray) = true
indexable(x) = false

nosignal(::Nothing) = error("Value is not a signal: nothing")
nosignal(x) = error("Value is not a signal: $x")

"""

    duration(x)

Return the duration of the signal in seconds, if known. May return `missing`
or [`inflen`](@ref). The value `missing` always denotes a finite but unknown
length.

!!! note

    If your are implementing a [custom signal](@ref custom_signals), you need not normally
    define `duration` as it will be computed from `nsamples` and `samplerate`.
    However, if one or both of these is `missing` and you want `duartion` to
    return a non-missing value, you can define custom method of `duration`.

"""
duration(x) = nsamples(x) / samplerate(x)
"""

    nsamples(x)

Returns the number of samples in the signal, if known. May return `missing`
or [`inflen`](@ref). The value `missing` always denotes a finite but unknown
length.

!!! note

    The return value of `nsamples` for a block (see [custom signals](@ref
    custom_signals) must be a non-missing, finite value.

"""
function nsamples
end

"""

    samplerate(x)

Returns the sample rate of the signal (in Hertz). May return `missing` if the
sample rate is unknown.

"""
function samplerate
end

"""

    nchannels(x)

Returns the number of channels in the signal.

"""
function nchannels
end

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

    If you pipe `signal` and pass a sample rate, you must specify the units
    of the sample rate (e.g. `x |> signal(20Hz)`). A unitless number is
    always interpreted as a constant, infinite-length signal (see below).

!!! note

    If you are implementing `signal` for a [custom signal](@ref
    custom_signals), you will need to support the second argument of `signal`
    by specifying `fs::Union{Number,Missing}=missing`, or equivalent, as your
    second argument.

The type of objects that can be coerced to signals are as follows.
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
        error("Signal expected to have sample rate of $(inHz(fs)) Hz.")
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
"""
    SiganlOperators.EvalTrait(x)

Indicates whether the signal is a `DataSignal` or
`ComputedSignal`. Data signals represent samples concretely
as a set of samples. Examples include arrays and numbers. Data signals
generally return themselves, or some wrapper type when `sink` is called on
them. Computed signals are any signal that invovles some intermediate
computation, in which samples must be computued on the fly. Calls to `sink`
on a computed signal results in some new, data signal. Most signals returned
by a signal operator are computed signals.

Computed signals have the extra responsibility of implementing
[`tosamplerate`](@ref)

"""
EvalTrait(x) = DataSignal()
EvalTrait(x::AbstractSignal) = ComputedSignal()
