export sink
using AxisArrays

# signals can be arrays with some metadata
function signal(x::AbstractArray,fs::Union{Missing,Number}=missing) 
    times = range(0s,length=size(x,1),step=s/inHz(fs))
    if ndims(x) == 1
        ax = AxisArray(x,Axis{:time}(times))
    elseif ndims(x) == 2
        channels = 1:size(x,2)
        ax = AxisArray(x,Axis{:time}(times),Axis{:channel}(channels))
    else
        error("To treat an array as a signal it must have 1 or 2 dimensions")
    end

    ax
end

function signal(x::AxisArray,fs::Union{Missing,Number}=missing)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    !isconsistent(fs,1/step(times))
    x
end
SignalTrait(::Type{<:AxisArray{T}}) where T = IsSignal{T,Float64,Int}()
nsamples(x::AxisArray) = length(AxisArrays.axes(x,Axis{:time}))
function nchannels(x::AxisArray) 
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    size(x,chdim)
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
@Base.propagate_inbounds function sampleat!(result,x::AxTimeD1,
    ::IsSignal,i::Number,j::Number)

    writesink(result,i,view(x,j,:))
end
@Base.propagate_inbounds function sampleat!(result,x::AxTimeD2,
    ::IsSignal,i::Number,j::Number)

    writesink(result,i,view(x,:,j))
end