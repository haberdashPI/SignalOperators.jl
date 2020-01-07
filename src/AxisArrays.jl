using .AxisArrays

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

nframes(x::AxisArray) = length(AxisArrays.axes(x,Axis{:time}))
function nchannels(x::AxisArray)
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    size(x,chdim)
end

function Signal(x::AxisArray,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have frame rate of $(inHz(fs)) Hz.")
    else
        x
    end
end

timeslice(x::AxTimeD1,indices) = view(x,indices,:)
timeslice(x::AxTimeD2,indices) = PermutedDimsArray(view(x,:,indices),(2,1))

function initsink(x,::Type{<:AxisArray})
    times = Axis{:time}(range(0s,length=nframes(x),step=float(s/samplerate(x))))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(initsink(x,Array),times,channels)
end
AxisArray(x::AbstractSignal) = sink(x,AxisArray)