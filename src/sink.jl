
"""
    sink([signal],[to];duration,samplerate)

Creates a given type of object (`to`) from a signal. By default the type of
the resulting sink is determined by the type of the underlying data of the
signal: e.g. if `x` is a `SampleBuf` object then `sink(mix(x,2))` is also a
`SampleBuf` object. If there is no underlying data (`signal(sin) |> sink`)
then the the type for the current backend is used
([`SignalOperators.set_array_backend`](@ref)).

## Array return type

When `to` is set to `Array` the return value is actually a tuple of an array
and a second value, which is the sample rate in Hertz. Thus, if you use the
default Array backend, you should use sink as follows:

    x,fs = sink(mysignal)

# Keyword arguments

## Sample Rate

The sample rate does not need to be specified, it will use either the sample
rate of `signal` or a default sample rate (which raises a warning). If
specified, the given sample rate is passed to [`signal`](@ref) when coercing
the input to a signal.

## Duration

You can limit the output of the given signal to the specified duration. If
this duration exceedes the duration of the passed signal an error will be
thrown.

# Values for `to`

## Type

If `to` is a type (e.g. `Array`) the signal is written to a value of that
type.

"""
sink(;kwds...) = x -> sink(x,refineroot(root(x));kwds...)
sink(to::Type;kwds...) = x -> sink(x,to;kwds...)
sink(x;kwds...) = sink(x,refineroot(root(x));kwds...)
root(x) = x
refineroot(x::AbstractArray) = typeof(x)
refineroot(x::Array) = curent_backend[]
refineroot(x) = curent_backend[]

mergepriority(x) = 0
mergepriority(x::Array) = 1
mergepriority(x::AbstractArray) = mergepriority(x,SignalTrait(x))
mergepriority(x::AbstractArray,::IsSignal) = 2
mergepriority(x::AbstractArray,::Nothing) = 0
function mergeroot(x,y)
    if mergepriority(x) ≥ mergepriority(y)
        return x
    else
        return y
    end
end

function sink(x,::Type{T};kwds...) where T <: AbstractArray
    x,n = process_sink_params(x;kwds...)
    result = initsink(x,T,n)
    sink!(result,x)
end

"""

    SignalOperators.initsink(x,::Type{T},len)

Initialize an object of type T so that it can store the first `len` samples
of signal `x`.

If you wish an object to serve as a [custom sink](@ref custom_sinks) you can
implement this method. You should probably use [`nchannels`](@ref) and
[`channel_eltype`](@ref) of `x` to determine how to initialize the object.

"""
initsink(x,::Type{<:Array},len) =
    (Array{channel_eltype(x)}(undef,len,nchannels(x)),samplerate(x))

function process_sink_params(x;duration=missing,
    samplerate=nothing)
    x = signal(x)

    if isnothing(samplerate)
        samplerate=SignalOperators.samplerate(x)
    end

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)
    duration = coalesce(duration,nsamples(x)*samples)

    if isinf(duration)
        error("Cannot store infinite signal. Specify a finite duration when ",
            "calling `sink`.")
    end

    n = insamples(Int,maybeseconds(duration),SignalOperators.samplerate(x))
    if n > nsamples(x)
        error("Requested signal duration is too long for passed signal: $x.")
    end

    x,n
end

"""

## Filename

If `to` is a string, it is assumed to describe the name of a file to which
the signal will be written. You will need to call `import` or `using` on an
appropriate backend for writing to the given file type.

Available backends include the following pacakges
- [WAV](https://codecov.io/gh/haberdashPI/SignalOperators.jl/src/master/src/WAV.jl)
- [LibSndFile](https://github.com/JuliaAudio/LibSndFile.jl)

"""
sink(to::String;kwds...) = x -> sink(x,to;kwds...)
function sink(x,to::String;kwds...)
    x,n = process_sink_params(x;kwds...)
    save_signal(filetype(to),to,x,n)
end
function save_signal(::Val{T},filename,x,len) where T
    error("No backend loaded for file of type $T. Refer to the documentation ",
          "of `signal` to find a list of available backends.")
end

"""
    sink!(array,x;[samplerate])

Write `size(array,1)` samples of signal `x` to `array`. If no sample rate has
been specified for `x` you can specify it now, using `samplerate` (it will
default to 44.1kHz).

"""
sink!(result::Union{AbstractVector,AbstractMatrix};kwds...) =
    x -> sink!(result,x;kwds...)
sink!(result::Tuple{<:AbstractArray,<:Number},x;kwds...) =
    (sink!(result[1],x;kwds...), result[2])
function sink!(result::Union{AbstractVector,AbstractMatrix},x;
    samplerate=SignalOperators.samplerate(x))

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)

    if nsamples(x) < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = tochannels(x,size(result,2))

    sink!(result,x,SignalTrait(x))
    result
end

"""

    SignalOperators.nextblock(x,maxlength,skip,[block])

Retrieve the next block of samples for signal `x`. The final, fourth argument
is optional. If it is left out, nextblock returns the first block of the
signal. The resulting block must has no more than `maxlength` samples, but
may have fewer samples than that; it should not have zero samples unless
`maxlength == 0`. If `skip == true`, it is guaranted that [`sample`](@ref)
will never be called on the returned block. The value of `skip` is `true`, for
example, when skipping blocks during a call to [`after`](@ref)).

"""
function nextblock
end

"""

    SignalOperators.timeslice(x::AbstractArray,indices)

Extract the slice of x with the given time indices.

[Custom signals](@ref custom_signals) can implement this method if the signal
is an `AbstractArray` allowing the use of a fallback implementation of
[`SignalOperators.nextblock`](@ref).

"""
function timeslice
end

"""

    SignalOperators.sample(x,block,i)

Retrieves the sample at index `i` of the given block of signal `x`. A sample
is one or more channels of `channel_eltype(x)` values. The return value
should be an indexable object (e.g. a number, tuple or array) of these
channel values. This method should be implemented by blocks of [custom
signals](@ref custom_signals).

"""
function sample
end

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal) =
    sink!(result,x,sig,nextblock(x,size(result,1),false))
function sink!(result,x,::IsSignal,block)
    written = 0
    while !isnothing(block) && written < size(result,1)
        @assert nsamples(block) > 0
        sink_helper!(result,written,x,block)
        written += nsamples(block)
        maxlen = size(result,1)-written
        if maxlen > 0
            block = nextblock(x,maxlen,false,block)
        end
    end
    @assert written == size(result,1)

    block
end


"""

    SignalOperators.sink_helper!(result,written,x,block)

Write the given `block` of samples from signal `x` to `result` given that
a total of `written` samples have already been written to the result.

This method should be fast: i.e. a for loop using @simd and @inbounds. It
should call [`nsamples`](@ref) and [`SignalOperators.sample`](@ref) on the
block to write the samples. **Do not call `sample` more than once for each
index of the block**.

"""
@noinline function sink_helper!(result,written,x,block)
    @inbounds @simd for i in 1:nsamples(block)
        writesink!(result,i+written,sample(x,block,i))
    end
end

@Base.propagate_inbounds function writesink!(result::AbstractArray,i,v)
    for ch in 1:length(v)
        result[i,ch] = v[ch]
    end
    v
end
