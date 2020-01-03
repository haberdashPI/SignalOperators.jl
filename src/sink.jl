
"""
    sink(signal,[to])

Creates a given type of object (`to`) from a signal. By default the type of
the resulting sink is determined by the type of the underlying data of the
signal: e.g. if `x` is a `SampleBuf` object then `sink(Mix(x,2))` is also a
`SampleBuf` object. If there is no underlying data (`Signal(sin) |> sink`)
then a Tuple of an array and the framerate is returned.

# Values for `to`

## Type

If `to` is an array type (e.g. `Array`, `DimensionalArray`) the signal is
written to a value of that type.

If `to` is a `Tuple` the result is an `Array` of samples and a number of
indicating the sample rate in Hertz.

"""
sink() = x -> sink(x,refineroot(root(x)))
sink(to::Type) = x -> sink(x,to)
sink(x) = sink(x,refineroot(root(x)))
root(x) = x
refineroot(x::AbstractArray) = refineroot(x,SignalTrait(x))
refineroot(x,::Nothing) = Tuple{<:AbstractArray,<:Number}
refineroot(x,::IsSignal) = typeof(x)
refineroot(x) = Tuple{<:AbstractArray,<:Number}
refineroot(x::T) where T <: Tuple{<:AbstractArray,<:Number} = T

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

function sink(x,::Type{T}) where T
    x = process_sink_params(x)
    result = initsink(x,T)
    sink!(result,x)
    result
end

function process_sink_params(x)
    x = Signal(x)

    fr = if ismissing(framerate(x))
        @warn("No frame rate was specified, defaulting to 44.1 kHz.")

        44.1kHz
    else
        framerate(x)
    end
    x = Signal(x,fr)

    if isinf(duration(x))
        error("Cannot store infinite signal. Specify a finite duration when ",
            "calling `sink`.")
    end

    x
end


"""

    SignalOperators.initsink(x,::Type{T},len)

Initialize an object of type T so that it can store the first `len` frames
of signal `x`.

If you wish an object to serve as a [custom sink](@ref custom_sinks) you can
implement this method. You should probably use [`nchannels`](@ref) and
[`channel_eltype`](@ref) of `x` to determine how to initialize the object.

"""
initsink(x,::Type{<:Array}) =
    Array{channel_eltype(x)}(undef,nframes(x),nchannels(x))
initsink(x,::Type{<:Tuple}) =
    (Array{channel_eltype(x)}(undef,nframes(x),nchannels(x)),framerate(x))
Array(x::AbstractSignal) = sink(x,Array)

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
function sink(x,to::String)
    x = process_sink_params(x)
    save_signal(filetype(to),to,x)
end
function save_signal(::Val{T},filename,x) where T
    error("No backend loaded for file of type $T. Refer to the documentation ",
          "of `Signal` to find a list of available backends.")
end

"""
    sink!(array,x;[framerate])

Write `size(array,1)` frames of signal `x` to `array`. If no frame rate has
been specified for `x` you can specify it now, using `framerate` (it will
default to 44.1kHz).

"""
sink!(result::Union{AbstractVector,AbstractMatrix};kwds...) =
    x -> sink!(result,x;kwds...)
sink!(result::Tuple{<:AbstractArray,<:Number},x;kwds...) =
    (sink!(result[1],x;kwds...), result[2])
function sink!(result::Union{AbstractVector,AbstractMatrix},x;
    framerate=SignalOperators.framerate(x))

    if ismissing(framerate) && ismissing(SignalOperators.framerate(x))
        @warn("No frame rate was specified, defaulting to 44.1 kHz.")
        framerate = 44.1kHz
    end
    x = Signal(x,framerate)

    if nframes(x) < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = ToChannels(x,size(result,2))

    sink!(result,x,SignalTrait(x))
    result
end

"""

    SignalOperators.nextblock(x,maxlength,skip,[block])

Retrieve the next block of frames for signal `x`. The final, fourth argument
is optional. If it is left out, nextblock returns the first block of the
signal. The resulting block must has no more than `maxlength` frames, but
may have fewer frames than that; it should not have zero frames unless
`maxlength == 0`. If `skip == true`, it is guaranted that [`frame`](@ref)
will never be called on the returned block. The value of `skip` is `true`, for
example, when skipping blocks during a call to [`After`](@ref)).

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

    SignalOperators.frame(x,block,i)

Retrieves the frame at index `i` of the given block of signal `x`. A frame
is one or more channels of `channel_eltype(x)` values. The return value
should be an indexable object (e.g. a number, tuple or array) of these
channel values. This method should be implemented by blocks of [custom
signals](@ref custom_signals).

"""
function frame
end

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal) =
    sink!(result,x,sig,nextblock(x,size(result,1),false))
function sink!(result,x,::IsSignal,block)
    written = 0
    while !isnothing(block) && written < size(result,1)
        @assert nframes(block) > 0
        sink_helper!(result,written,x,block)
        written += nframes(block)
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

Write the given `block` of frames from signal `x` to `result` given that
a total of `written` frames have already been written to the result.

This method should be fast: i.e. a for loop using @simd and @inbounds. It
should call [`nframes`](@ref) and [`SignalOperators.frame`](@ref) on the
block to write the frames. **Do not call `frame` more than once for each
index of the block**.

"""
@noinline function sink_helper!(result,written,x,block)
    @inbounds @simd for i in 1:nframes(block)
        writesink!(result,i+written,frame(x,block,i))
    end
end

@Base.propagate_inbounds function writesink!(result::AbstractArray,i,v)
    for ch in 1:length(v)
        result[i,ch] = v[ch]
    end
    v
end
