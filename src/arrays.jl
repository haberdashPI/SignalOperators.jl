export sink
using AxisArrays

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Any array can be interpreted as a signal. By default the first dimension is
time, the second channels and their sample rate is a missing value. Some
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
        arraysignal(x,curent_backend[],fs)
    end
end

arraysignal(x,::Type{<:Array},fs) = (x,inHz(fs))

tosamplerate(x::AbstractArray,::IsSignal{<:Any,Missing},::DataSignal,fs::Number;blocksize) =
    signal(x,fs)
tosamplerate(x::AbstractArray,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize) =
    __tosamplerate__(x,s,fs,blocksize)

function SignalTrait(::Type{<:AbstractArray{T,N}}) where{T,N}
    if N ∈ [1,2]
        IsSignal{T,Missing,Int}()
    else
        error("Array must have 1 or 2 dimensions to be treated as a signal.")
    end
end

nsamples(x::AbstractVecOrMat) = size(x,1)
nchannels(x::AbstractVecOrMat) = size(x,2)
samplerate(x::AbstractVecOrMat) = missing

timeslice(x::AbstractArray,indices) = view(x,indices,:)

"""

## Array & Number

A tuple of an array and a number can be interepted as a signal. The first
dimension is time, the second channels, and the number determines the sample
rate (in Hertz).

"""
function signal(x::Tuple{<:AbstractArray,<:Number},
    fs::Union{Missing,Number}=missing)

    if !isconsistent(fs,x[2])
        error("Signal expected to have sample rate of $(inHz(fs)) Hz.")
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

nsamples(x::Tuple{<:AbstractVecOrMat,<:Number}) = size(x[1],1)
nchannels(x::Tuple{<:AbstractVecOrMat,<:Number}) = size(x[1],2)
samplerate(x::Tuple{<:AbstractVecOrMat,<:Number}) = x[2]
timeslice(x::Tuple{<:AbstractVecOrMat,<:Number}) = view(x[1],indices,:)
function nextblock(x::Tuple{<:AbstractVecOrMat,<:Number},maxlen,skip,
    block=ArrayBlock([],0))

    nextblock(x[1],maxlen,skip,block)
end

"""
    ArrayBlock{A,S}(data::A,state::S)

A straightforward implementation of blocks as an array and a custom state.
The array allows a generic implementation of [`nsamples`](@ref) and
[`SignalOperators.sample`](@ref). The fields of this struct are `data` and
`state`.

[Custom signals](@ref custom_signals) can return an `ArrayBlock` from
[`SignalOperators.nextblock`](@ref) to allow for fallback implementations of
[`nsamples`](@ref) and [`SignalOperators.sample`](@ref).

"""
struct ArrayBlock{A,S}
    data::A
    state::S
end

nsamples(block::ArrayBlock) = size(block.data,1)
@Base.propagate_inbounds sample(x,block::ArrayBlock,i) = view(block.data,i,:)

function nextblock(x::AbstractArray,maxlen,skip,block = ArrayBlock([],0))
    offset = block.state + nsamples(block)
    if offset < nsamples(x)
        len = min(maxlen,nsamples(x)-offset)
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
function signalshow(io,x::AxisArray)
    signalshow(io,x.data)
    show_fs(io,x)
end

mergerule(::Type{<:AbstractArray},y::Type{<:AbstractArray}) = Array

################################################################################
# Axis Arrays
function SignalTrait(::Type{<:AxisArray{T,N}}) where {T,N}
    if N ∈ [1,2]
        IsSignal{T,Float64,Int}()
    else
        error("Array must have 1 or 2 dimensions to be treated as a signal.")
    end
end

function samplerate(x::AxisArray)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    inHz(1/step(times))
end

const WithAxes{Tu} = AxisArray{<:Any,<:Any,<:Any,Tu}
const AxTimeD1 = Union{
    WithAxes{<:Tuple{Axis{:time}}},
    WithAxes{<:Tuple{Axis{:time},<:Any}}}
const AxTimeD2 = WithAxes{<:Tuple{<:Any,Axis{:time}}}
const AxTime = Union{AxTimeD1,AxTimeD2}

nsamples(x::AxisArray) = length(AxisArrays.axes(x,Axis{:time}))
function nchannels(x::AxisArray)
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    size(x,chdim)
end

function arraysignal(x,::Type{<:AxisArray},fs)
    if ndims(x) == 1
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        AxisArray(x,Axis{:time}(times))
    elseif ndims(x) == 2
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        channels = 1:size(x,2)
        AxisArray(x,Axis{:time}(times),Axis{:channel}(channels))
    else
        errordim()
    end
end

function signal(x::AxisArray,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

timeslice(x::AxTimeD1,indices) = view(x,indices,:)
timeslice(x::AxTimeD2,indices) = PermutedDimsArray(view(x,:,indices),(2,1))
