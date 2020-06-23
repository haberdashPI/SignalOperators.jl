
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
sink() = x -> sink(x,refineroot(root(x)))
sink(to::Type) = x -> sink(x,to)
sink(x) = sink(x,refineroot(root(x)))
root(x) = x
refineroot(x::AbstractArray) = refineroot(x,SignalTrait(x))
refineroot(x,::Nothing) = Tuple{<:AbstractArray,<:Number}
refineroot(x,::IsSignal{<:Any,Missing}) = Array
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

abstract type CutMethod
end
struct DataCut <: CutMethod
end
struct SinkCut <: CutMethod
end
CutMethod(x) = CutMethod(x,EvalTrait(x))
CutMethod(x,::DataSignal) = SinkCut()
CutMethod(x::AbstractArray,::DataSignal) = DataCut()
CutMethod(x::Tuple{<:AbstractArray,<:Number},::DataSignal) = DataCut()
CutMethod(x,::ComputedSignal) = SinkCut()

sink(x,::Type{T}) where T = sink(x,T,CutMethod(x))
function sink(x,::Type{T},::DataCut) where T
    x = process_sink_params(x)
    data = timeslice(x,:)
    if Base.typename(typeof(parent(data))) == Base.typename(T)
        data
    else # if the sink type is new, we have to copy the data
        # because it could be in a different memory layout
        result = initsink(x,T)
        sink!(result,x)
        result
    end
end
rawdata(x::SubArray) = x
function rawdata(x::AbstractArray)
    p = parent(x)
    if p === x
        return p
    else
        return rawdata(p)
    end
end

function sink(x,::Type{T},::SinkCut) where T
    x = process_sink_params(x)
    result = initsink(x,T)
    sink!(result,x)
    result
end

function process_sink_params(x)
    x = Signal(x)
    ismissing(nframes(x)) && error("Unknown number of frames in signal.")
    isinf(nframes(x)) && error("Cannot store infinite signal.")
    x
end


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

    SignalOperators.iterateblock(signal,N,[state])

Return the next block of data from `signal`. Analogous to [`iterate`](@ref
Base.iterate), `iterateblock` returns the data, and an internal state for subsequent
iterations. The returned data is a value, `block`, which can be any array-like object:
specifically, `block` can be any object which implements [`size`](@ref Base.size)
[`ndims`](@ref Base.ndims), and [`iterate`](@ref Base.iterate). Data must iterate in
column-major order.

## Arugments

- `signal`: the signal to retrieve blocks from
- `N`: the maximum number of frames the returned block should have.
- `state` The second argument should pass the previous state of the last call to
    `iterateblock!`. If it is left out, nextblock returns the very first block of the
    signal.

"""
function iterateblock
end

struct IsSignalBlock; end

"""
    SignalBlock(x)

A trait: if the return value of `SignalBlock` is `IsSignalBlock()` then `x`
implements `iterate` with return value `sampletype(x)` and [`eachtimeslice`](x).
"""
SignalBlock(x) = nothing
SignalBlock(x::AbstractArray) = x

block_nframes(x) = size(x)[end]

__getframes__(x::AbstractArray,ixs) = @view x[(Base.Colon() for _=1:ndims(x)-1)...,ixs]
__setframes__(x::AbstractArray,ixs,vals) =
    x[(Base.Colon() for _=1:ndims(x)-1)...,ixs] = vals

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal) =
    sink!(result,x,sig,iterateblock!(x,result))
function sink!(result,x,::IsSignal,block)
    written = 0
    N = size(result,ndims(result))
    while !isnothing(block) && written < block_nframes(result)
        data, state = block
        n = block_nframes(data)
        @assert n > 0
        copyto!(__getframes__(result,(1:N) .+ written), data)
        written += n
        m = block_nframes(result)-written
        if m > 0
            block = nextblock(x,m,state)
        end
    end
    @assert written == nframes(result)

    # return the state (for internal purposes) if available
    if !isnothing(block)
        return block[2]
    end
end
