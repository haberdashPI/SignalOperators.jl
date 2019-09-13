export sink
using AxisArrays

errordim() = error("To treat an array as a signal it must have 1 or 2 dimensions")

# signals can be arrays with some metadata
"""
## Arrays

Arrays can be treated as signals. The first dimension is time, the second
channels. 

[`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl), if they have an
axis labled `time` and one or zero additioanl axes, can be treated as a signal.
The time dimension must be represted using a `Range`.

"""
function signal(x::AbstractArray{<:Any,N},::IsSignal,
    fs::Union{Missing,Number}=missing) where N

    if N == 1
        ismissing(fs) && return x
        times = range(0s,length=size(x,1),step=s/inHz(fs))
        AxisArray(x,Axis{:time}(times))
    elseif N == 2
        ismissing(fs) && return x
        times = range(0s,length=size(x,1),step=s/inHz(fs))
        channels = 1:size(x,2)
        AxisArray(x,Axis{:time}(times),Axis{:channel}(channels))
    else
        errordim()
    end
end

function signal(x::AxisArray,::IsSignal,fs::Union{Missing,Number}=missing)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    !isconsistent(fs,1/step(times))
    x
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
@Base.propagate_inbounds function sampleat!(result,x::AxTimeD1,
    ::IsSignal,i::Number,j::Number,check)

    writesink(result,i,view(x,j,:))
end
@Base.propagate_inbounds function sampleat!(result,x::AxTimeD2,
    ::IsSignal,i::Number,j::Number,check)

    writesink(result,i,view(x,:,j))
end