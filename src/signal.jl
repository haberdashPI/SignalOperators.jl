export duration, nframes, framerate, nchannels, Signal, sink, sink!, channel_eltype
using FileIO

# Signals have a frame rate and some iterator element type
# T, which is an NTuple{N,<:Number}.
"""
    SignalOperators.IsSignal{T,Fs,L}

Represents the Format of a signal type with three type parameters:

* `T` - The [`channel_eltype`](@ref) of the signal.
* `Fs` - The type of the framerate. It should be either `Float64` or
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

channeltype(x::AbstractSignal) = channeltype(x,SignalTrait(x))
channeltype(x,::IsSignal{T}) where T = T

IsSignal{T}(fs::Fs,len::L) where {T,Fs,L} = IsSignal{T,Fs,L}()

function show_fs(io,x)
    if !get(io,:compact,false) && !ismissing(framerate(x))
        write(io," (")
        show(io, MIME("text/plain"), framerate(x))
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


nosignal(::Nothing) = error("Value is not a signal: nothing")
nosignal(x) = error("Value is not a signal: $x")

isconsistent(fs,_fs) = ismissing(fs) || inHz(_fs) == inHz(fs)

"""
    Signal(x,[framerate])

Coerce `x` to be a signal, optionally specifying its frame rate (usually in
Hz). All signal operators first call `Signal(x)` for each argument. This
means you only need to call `Signal` when you want to pass additional
arguments to it.

!!! note

    If you pipe `Signal` and pass a frame rate, you must specify the units of
    the frame rate (e.g. `x |> Signal(20Hz)`). A unitless number is always
    interpreted as a constant, infinite-length signal (see below).

!!! note

    If you are implementing `Signal` for a [custom signal](@ref
    custom_signals), you will need to support the second argument of `Signal`
    by specifying `fs::Union{Number,Missing}=missing`, or equivalent.

The type of objects that can be coerced to signals are as follows.
"""
Signal(;kwds...) = x -> Signal(x;kwds...)
Signal(fs::Quantity;kwds...) = x -> Signal(x,fs;kwds...)
Signal(x,fs::Union{Number,Missing}=missing) = Signal(x,SignalTrait(x),fs)
Signal(x,::Nothing,fs) = error("Don't know how create a signal from $x.")

function filetype(x)
    m = match(r".+\.([^\.]+$)",x)
    if isnothing(m)
        error("The file \"$x\" has no filetype.")
    else
        DataFormat{Symbol(uppercase(m[1]))}()
    end
end

"""

## Filenames

A string with a filename ending with an appropriate filetype can be read in
as a signal. You will need to call `import` or `using` on the backend for
reading the file.

Available backends include the following pacakges
- [WAV](https://github.com/dancasimiro/WAV.jl)
- [LibSndFile](https://github.com/JuliaAudio/LibSndFile.jl)

"""
Signal(x::String,fs::Union{Missing,Number}=missing) =
    load_signal(filetype(x),x,fs)

function load_signal(::DataFormat{T},x,fs) where T
    error("No backend loaded for file of type $T. Refer to the ",
          "documentation of `Signal` to find a list of available backends.")
end

"""

## Existing signals

Any existing signal just returns itself from `Signal`. If a frame rate is
specified it will be set if `x` has an unknown frame rate. If it has a known
frame rate and doesn't match `framerate(x)` an error will be thrown. If
you want to change the frame rate of a signal use [`ToFramerate`](@ref).

"""
function Signal(x,::IsSignal,fs)
    if ismissing(framerate(x))
        ToFramerate(x,fs)
    elseif !isconsistent(fs,framerate(x))
        error("Signal expected to have frame rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

# computed signals have to implement there own version of ToFramerate
# (e.g. resample) to avoid inefficient computations

struct DataSignal
end
struct ComputedSignal
end
"""
    SiganlOperators.EvalTrait(x)

Indicates whether the signal is a `DataSignal` or
`ComputedSignal`. Data signals represent frames concretely
as a set of frames. Examples include arrays and numbers. Data signals
generally return themselves, or some wrapper type when `sink` is called on
them. Computed signals are any signal that invovles some intermediate
computation, in which frames must be computued on the fly. Calls to `sink`
on a computed signal results in some new, data signal. Most signals returned
by a signal operator are computed signals.

Computed signals have the extra responsibility of implementing
[`ToFramerate`](@ref)

"""
EvalTrait(x) = DataSignal()
EvalTrait(x::AbstractSignal) = ComputedSignal()