export sink

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Any array can be interpreted as a signal. By default the first dimension is
time, the second channels and their frame rate is a missing value. Some
array types change this default behavior.

- [`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl), if they have an
axis labeled `time` and one or zero additional axes, can be treated as a
signal. The time dimension must be represented using on object with the `step`
function defined (e.g. any `AbstractRange` object).
- [`SampleBuf`](https://github.com/JuliaAudio/SampledSignals.jl) objects are
also properly interpreted as signals, as per the conventions employed for its
package.
- [`DimensionalArrays`](https://github.com/rafaqz/DimensionalData.jl) can be
treated as signals if there is a `Time` dimension, which must be represented
using an object with the `step` function defined (e.g. `AbstractRange`)

"""
function signal(x::AbstractArray,fs::Union{Missing,Number}=missing)
    if ismissing(fs)
        if ndims(x) ∈ [1,2]
            return x
        else
            errordim()
        end
    else
        arraysignal(x,current_backendl[],fs)
    end
end

arraysignal(x,::Type{<:Array},fs) = (x,inHz(fs))

toframerate(x::AbstractArray,::IsSignal{<:Any,Missing},::DataSignal,fs::Number;blocksize) =
    signal(x,fs)
toframerate(x::AbstractArray,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize) =
    __toframerate__(x,s,fs,blocksize)

function SignalTrait(::Type{<:AbstractArray{T,N}}) where{T,N}
    if N ∈ [1,2]
        IsSignal{T,Missing,Int}()
    else
        error("Array must have 1 or 2 dimensions to be treated as a signal.")
    end
end

nframes(x::AbstractVecOrMat) = size(x,1)
nchannels(x::AbstractVecOrMat) = size(x,2)
framerate(x::AbstractVecOrMat) = missing

timeslice(x::AbstractArray,indices) = view(x,indices,:)

"""

## Array & Number

A tuple of an array and a number can be interepted as a signal. The first
dimension is time, the second channels, and the number determines the frame
rate (in Hertz).

"""
function signal(x::Tuple{<:AbstractArray,<:Number},
    fs::Union{Missing,Number}=missing)

    if !isconsistent(fs,x[2])
        error("Signal expected to have frame rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

function SignalTrait(::Type{<:Tuple{<:AbstractArray{T,N},<:Number}}) where {T,N}
    if N ∈ [1,2]
        IsSignal{T,Float64,Int}()
    else
        error("Array must have 1 or 2 dimensions to be treated as a signal.")
    end
end

nframes(x::Tuple{<:AbstractVecOrMat,<:Number}) = size(x[1],1)
nchannels(x::Tuple{<:AbstractVecOrMat,<:Number}) = size(x[1],2)
framerate(x::Tuple{<:AbstractVecOrMat,<:Number}) = x[2]
timeslice(x::Tuple{<:AbstractVecOrMat,<:Number}) = view(x[1],indices,:)
function nextblock(x::Tuple{<:AbstractVecOrMat,<:Number},maxlen,skip,
    block=ArrayBlock([],0))

    nextblock(x[1],maxlen,skip,block)
end

"""
    ArrayBlock{A,S}(data::A,state::S)

A straightforward implementation of blocks as an array and a custom state.
The array allows a generic implementation of [`nframes`](@ref) and
[`SignalOperators.frame`](@ref). The fields of this struct are `data` and
`state`.

[Custom signals](@ref custom_signals) can return an `ArrayBlock` from
[`SignalOperators.nextblock`](@ref) to allow for fallback implementations of
[`nframes`](@ref) and [`SignalOperators.frame`](@ref).

"""
struct ArrayBlock{A,S}
    data::A
    state::S
end

nframes(block::ArrayBlock) = size(block.data,1)
@Base.propagate_inbounds frame(x,block::ArrayBlock,i) = view(block.data,i,:)

function nextblock(x::AbstractArray,maxlen,skip,block = ArrayBlock([],0))
    offset = block.state + nframes(block)
    if offset < nframes(x)
        len = min(maxlen,nframes(x)-offset)
        ArrayBlock(timeslice(x,offset .+ (1:len)),offset)
    end
end

function signaltile(x)
    io = IOBuffer()
    signalshow(io,x)
    literal(String(take!(io)))
end
function signalshow(io,x::AbstractArray)
    show(IOContext(io,:displaysize=>(1,30),:limit=>true),
        MIME("text/plain"),x)
    show_fs(io,x)
end

mergerule(::Type{<:AbstractArray},y::Type{<:AbstractArray}) = Array
