export sink
using AxisArrays

# signals can be arrays with some metadata
function signal(x::AbstractArray,fs=missing) 
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

function signal(x::AxisArray,fs=missing)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    !isconsistent(fs,1/step(times))
    x
end
SignalTrait(::Type{<:AxisArray{T}}) where T = IsSignal{T,Float64,Int}()
nsamples(x::AxisArray) = length(AxisArrays.axes(x,Axis{:time})[1])
function nchannels(x::AxisArrays) 
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    size(x,chdim)
end
function samplerate(x::AxisArray)
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    inHz(1/step(times))
end

struct TimeSlices{D,A <: AbstractArray} 
    data::A
end
TimeSlices(x::A) where{A} = TimeSlices{1,A}(x)
TimeSlices{D}(x::A) where{D,A} = TimeSlices{D,A}(x)
function samples(x::AxisArray,::IsSignal) 
    axisdim(x,Axis{:time}) == 1 ? TimeSlices(x) : TimeSlices{2}(x)
end

function sink(x::AxisArray,::IsSignal)
    axisdim(x,Axis{:time}) == 1 ? x : permutedims(x,[2,1])
end

Base.iterate(x::TimeSlices{<:Any,1},i=1) =
    i ≤ size(x.data,1) ? (Tuple(view(getcontents(x.data),i,:)), i+1) : nothing
Base.iterate(x::TimeSlices{<:Any,2},i=1) =
    i ≤ size(x.data,2) ? (Tuple(view(getcontents(x.data),:,i)), i+1) : nothing

function Base.Iterators.take(x::TimeSlices{N,1},n::Integer) where N
    view = @views(getcontents(x.data)[1:n,:])
    TimeSlices{N,1}(view)
end
function Base.Iterators.drop(x::TimeSlices{N,1},n::Integer) where N
    view = @views(getcontents(x.data)[n+1:end,:])
    TimeSlices{N,1}(view)
end
function Base.Iterators.take(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,1:n])
    TimeSlices{N,2}(view)
end
function Base.Iterators.drop(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,n+1:end])
    TimeSlices{N,2}(view)
end
Base.Iterators.IteratorSize(::Type{<:TimeSlices}) = Iterators.HasLength()
Base.length(x::TimeSlices{<:Any,D}) where D = size(x.data,D)
