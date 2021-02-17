export sink

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Any array can be interpreted as a signal. By default the last dimension is
time.

If you specify a non-missing frame rate to an array type with a missing frame
rate, the return value will be a Tuple (see Array & Number
section below).

Some array types change these default behaviors, as follows.

- [`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl), if they have an
    axis labeled `time` and one or zero additional axes, can be treated as a
    signal. The time dimension must be represented using on object with the `step`
    function defined (e.g. any `AbstractRange` object).
- [`SampleBuf`](https://github.com/JuliaAudio/SampledSignals.jl) objects are
    also properly interpreted as signals, as per the conventions employed for its
    package.
- [`DimensionalArrays`](https://github.com/rafaqz/DimensionalData.jl) can be
    treated as signals if there is a `Time` dimension, which must be represented
    using an object with the `step` function defined (e.g. `AbstractRange`).

"""
function Signal(x::AbstractArray,fs::Union{Missing,Number}=missing)
    if ismissing(fs)
        return x
    else
        (x,Float64(inHz(fs)))
    end
end

ToFramerate(x::AbstractArray,::IsSignal{<:Any,Missing},::DataSignal,fs::Number;blocksize) =
    Signal(x,fs)
ToFramerate(x::AbstractArray,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize) =
    __ToFramerate__(x,s,fs,blocksize)

SignalTrait(::Type{<:AbstractArray{T,N}}) where{T,N} = IsSignal{T,Missing,Int}()

SignalBase.nframes(x::AbstractArray) = size(x,1)
SignalBase.nchannels(x::AbstractArray) = size(x,2)
SignalBase.sampletype(x::AbstractArray) = eltype(x)
SignalBase.framerate(x::AbstractArray) = missing
sink(x::AbstractArray, ::IsSignal, n) =
    view(x, axes(x)[1:(end-1)]..., firstindex(x) .+ (0:(n-1)))

"""

## Array & Number

A tuple of an array and a number can be interepted as a signal. The last
dimension is time, and the number determines the frame
rate (in Hertz).

"""
function Signal(x::Tuple{<:AbstractArray,<:Number},
    fs::Union{Missing,Number}=missing)

    if !isconsistent(fs,x[2])
        error("Signal expected to have frame rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

function SignalTrait(::Type{<:Tuple{<:AbstractArray{T,N},<:Number}}) where {T,N}
    IsSignal{T,Float64,Int}()
end

SignalBase.nframes(x::Tuple{<:AbstractArray,<:Number}) = size(x[1],1)
SignalBase.nchannels(x::Tuple{<:AbstractArray,<:Number}) = size(x[1],2)
SignalBase.framerate(x::Tuple{<:AbstractArray,<:Number}) = x[2]
SignalBase.sampletype(x::Tuple{<:AbstractArray,<:Number}) = eltype(x[1])
sink(x::Tuple{<:AbstractArray,<:Number}, ::IsSignal, n) =
    view(x[1], axes(x)[1:(end-1)]..., firstindex(x) .+ (0:(n-1)))

function signaltile(x)
    io = IOBuffer()
    signalshow(io,x)
    literal(String(take!(io)))
end
function signalshow(io,x::AbstractArray,shownfs=false)
    p = parent(x)
    if p === x
        show(IOContext(io,:displaysize=>(1,30),:limit=>true),
            MIME("text/plain"),x)
        !shownfs && show_fs(io,x)
    else
        signalshow(io,p,true)
        show_fs(io,x)
    end
end
function signalshow(io,x::Tuple{<:AbstractArray,<:Number},shownfs=false)
    signalshow(io,x[1],true)
    show_fs(io,x)
end
