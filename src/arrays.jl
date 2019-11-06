export sink
using AxisArrays

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Arrays can be treated as signals. The first dimension is time, the second
channels.

[`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl), if they have an
axis labeled `time` and one or zero additional axes, can be treated as a
signal. The time dimension must be represented using on object with the `step`
function defined (e.g. any `AbstractRange`).

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
tosamplerate(x::AxisArray,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize) =
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

nsamples(block::AbstractArray) = size(block,1)
@Base.propagate_inbounds sample(x,block::AbstractArray,i) = view(block,i,:)

function nextblock(x::AxTime,maxlen,skip,block = _view(x,1:0))
    offset = _nextoffset(x,block)
    if offset < nsamples(x)
        len = min(maxlen,nsamples(x)-offset)
        _view(x,offset .+ (1:len))
    end
end
_nextoffset(x::SubArray) = last(x.indices[1])
_nextoffset(x::AbstractArray) = _nextoffset(parent(x))
_nextoffset(x::AxTimeD1,block) = _nextoffset(block)
_nextoffset(x::AxTimeD2,block) = _nextoffset(block)
_view(x::AxTimeD1,indices) = view(x,indices,:)
_view(x::AxTimeD2,indices) = PermutedDimsArray(view(x,:,indices),(2,1))

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