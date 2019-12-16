export sink
using AxisArrays

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Arrays can be interpreted as signals. The first dimension is time, the second
channels. By default their sample rate is a missing value.

[`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl), if they have an
axis labeled `time` and one or zero additional axes, can be treated as a
signal. The time dimension must be represented using on object with the `step`
function defined (e.g. any `AbstractRange` object).

[`SampleBuf`](https://github.com/JuliaAudio/SampledSignals.jl) objects are
also properly interpreted as signals.

"""
function signal(x::AbstractArray{<:Any,N},::IsSignal,
    fs::Union{Missing,Number}=missing) where N

    if N == 1
        ismissing(fs) && return x
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        AxisArray(x,Axis{:time}(times))
    elseif N == 2
        ismissing(fs) && return x
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        channels = 1:size(x,2)
        AxisArray(x,Axis{:time}(times),Axis{:channel}(channels))
    else
        errordim()
    end
end
function signal(x::AxisArray,::IsSignal,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

tosamplerate(x::AbstractArray,::IsSignal{<:Any,Missing},::DataSignal,fs::Number;blocksize) =
    signal(x,fs)
tosamplerate(x::AbstractArray,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize) =
    __tosamplerate__(x,s,fs,blocksize)


function SignalTrait(::Type{A}) where{T,N,A<:AbstractArray{T,N}}
    if N ∈ [1,2]
        if A <: AxisArray
            IsSignal{T,Float64,Int}()
        else
            IsSignal{T,Missing,Int}()
        end
    else
        error("Array must have 1 or 2 dimensions to be treated as a signal.")
    end
end

nsamples(x::AxisArray) = length(AxisArrays.axes(x,Axis{:time}))
nsamples(x::AbstractVecOrMat) = size(x,1)

function nchannels(x::AxisArray)
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    size(x,chdim)
end
nchannels(x::AbstractVecOrMat) = size(x,2)
function samplerate(x::AxisArray)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    inHz(1/step(times))
end
samplerate(x::AbstractVecOrMat) = missing

const WithAxes{Tu} = AxisArray{<:Any,<:Any,<:Any,Tu}
const AxTimeD1 = Union{
    WithAxes{<:Tuple{Axis{:time}}},
    WithAxes{<:Tuple{Axis{:time},<:Any}}}
const AxTimeD2 = WithAxes{<:Tuple{<:Any,Axis{:time}}}
const AxTime = Union{AxTimeD1,AxTimeD2}

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

timeslice(x::AxTimeD1,indices) = view(x,indices,:)
timeslice(x::AxTimeD2,indices) = PermutedDimsArray(view(x,:,indices),(2,1))

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