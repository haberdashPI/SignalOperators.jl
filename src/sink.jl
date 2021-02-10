
"""
    sink(signal,[to])

Creates a given type of object (`to`) from a signal. By default the type of
the resulting sink is determined by the type of the underlying data of the
signal: e.g. if `x` is a `SampleBuf` object then `sink(Mix(x,2))` is also a
`SampleBuf` object. If there is no underlying data (`Signal(sin) |> sink`)
then a Tuple of an array and the framerate is returned.

!!! warning

    Though `sink` often makes a copy of an input array, it is not guaranteed
    to do so. For instance `sink(Until(rand(10),5frames))` will simply take a view
    of the first 5 frames of the input.

# Values for `to`

## Type

If `to` is an array type (e.g. `Array`, `DimensionalArray`) the signal is
written to a value of that type.

If `to` is a `Tuple` the result is an `Array` of samples and a number
indicating the sample rate in Hertz.

"""
sink(x::AbstractArray) = x
sink(x::T, ::Type{S}) where {T <: S, S <: AbstractArray} = x
sink(x::T, Type{S}) where {T <: AbstractArray, S} = convert(S, x)

"""

    SignalOperators.initsink(x,::Type{T})

Initialize an object of type T so that it can store all frames of signal `x`.

If you wish an object to serve as a [custom sink](@ref custom_sinks) you can
implement this method. You can use [`nchannels`](@ref) and
[`sampletype`](@ref) of `x` to determine how to initialize the object for the
first method, or you can just use `initsink(x,Array)` and wrap the return
value with your custom type.

"""
function initsink(x,::Type{<:Array})
    Array{sampletype(x),2}(undef,nframes(x),nchannels(x))
end
initsink(x,::Type{<:Tuple}) =
    (Array{sampletype(x)}(undef,nframes(x),nchannels(x)),framerate(x))
initsink(x,::Type{<:Array},data) = data
initsink(x,::Type{<:Tuple},data) = (data,framerate(x))
Base.Array(x::AbstractSignal) = sink(x,Array)
Base.Tuple(x::AbstractSignal) = sink(x,Tuple)

"""

## Filename

If `to` is a string, it is assumed to describe the name of a file to which
the signal will be written. You will need to call `import` or `using` on an
appropriate backend for writing to the given file type.

Available backends include the following pacakges
- [WAV](https://codecov.io/gh/haberdashPI/SignalOperators.jl/src/master/src/WAV.jl)
- [LibSndFile](https://github.com/JuliaAudio/LibSndFile.jl)

"""
sink(to::String) = x -> sink(x,to)
function sink(x,to::String)
    x = process_sink_params(x)
    save_signal(filetype(to),to,x)
end
function save_signal(::Val{T},filename,x) where T
    error("No backend loaded for file of type $T. Refer to the documentation ",
          "of `Signal` to find a list of available backends.")
end

"""
    sink!(array,x)

Write `size(array,1)` frames of signal `x` to `array`.

"""
sink!(result::Union{AbstractVector,AbstractMatrix}) =
    x -> sink!(result,x)
sink!(result::Tuple{<:AbstractArray,<:Number},x) =
    (sink!(result[1],x), result[2])
function sink!(result::Union{AbstractVector,AbstractMatrix},x;
    framerate=SignalOperators.framerate(x))

    if nframes(x) < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = ToChannels(x,size(result,2))

    sink!(result,x,SignalTrait(x))
    result
end

"""

    SignalOperators.nextblock(x,maxlength,skip,[last_block])

Retrieve the next block of frames for signal `x`, or nothing, if no more
blocks exist. Analogous to `Base.iterate`. The returned block must satisfy
the interface for signal blocks as described in [custom signals](@ref
custom_signals).

## Arugments

- `x`: the signal to retriev blocks from
- `maxlength`: The resulting block must have no more than `maxlength` frames,
    but may have fewer frames than that; it should not have zero frames unless
    `maxlength == 0`.
- `skip`: If `skip == true`, it is guaranted that [`frame`](@ref)
    will never be called on the returned block. The value of `skip` is `true`
    when skipping blocks during a call to [`After`](@ref)).
- `last_block` The fourth argument is optional. If included, the block that
    occurs after this block is returned. If it is left out, nextblock returns the
    very first block of the signal.

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
is one or more channels of `sampletype(x)` values. The return value
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
    @assert written == nframes(result)

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
