export sink
using AxisArrays

# signals can be arrays with some metadata
const ArraySignal{El} = MetaArray{<:AxisArray,<:IsSignal{El}} where El
function signal(x::AbstractArray,fs) 
    if !(1 ≤ ndims(x) ≤ 2)
        error("To treat an array as a signal it must have 1 or 2 dimensions")
    end
    times = range(0s,length=size(x,1),step=s/inHz(fs))
    channels = 1:size(x,2)
    ax = AxisArray(x,Axis{:time}(times),Axis{:channel}(channels))
    MetaArray(IsSignal{NTuple{size(x,2),eltype(x)}}(inHz(fs)),ax)
end
function signal(x::AxisArray,fs=missing)
    if !(1 ≤ ndims(x) ≤ 2)
        error("Expected AxisArray to have one or two dimensions")
    end
    times = axisvalues(AxisArrays.axes(x,Axis{:time}))[1]
    !checksamplerate(inHz(fs),inHz(1/step(times)))
    fs = inHz(1/step(times))

    time ∈ axisnames(x)
    chdim = axisdim(x,Axis{:time}) == 1 ? 2 : 1
    MetaArray(IsSignal{NTuple{size(x,chdim),eltype(x)}}(fs),x)
end
signal(x::ArraySignal) = x
SignalTrait(x::ArraySignal) = getmeta(x)
signal_eltype(::Type{<:ArraySignal{T}}) where T = T

struct TimeSlices{N,D,A <: AbstractArray} 
    data::A
end
TimeSlices{N}(x::A) where{N,A} = TimeSlices{N,1,A}(x)
TimeSlices{N,D}(x::A) where{N,D,A} = TimeSlices{N,D,A}(x)
function samples(x::ArraySignal,::IsSignal) 
    if axisdim(x,Axis{:time}) == 1
        TimeSlices{size(x,1)}(x,samplerate(x))
    else
        TimeSlices{size(x,1),2}(x,samplerate(x))
    end
end

function sink(x::ArraySignal,::IsSignal)
    if axisdim(x,Axis{:time}) == 1
        x
    else
        permutedims(x,[2,1])
    end
end

Base.iterate(x::TimeSlices{<:Any,1},i=1) =
    i ≤ size(x.data,1) ? (Tuple(view(getcontents(x.data),i,:)), i+1) : nothing
Base.iterate(x::TimeSlices{<:Any,2},i=1) =
    i ≤ size(x.data,2) ? (Tuple(view(getcontents(x.data),:,i)), i+1) : nothing

# NOTE: the below is a workaround of limitations in the interface
# for MetaArray
function Base.Iterators.take(x::TimeSlices{N,1},n::Integer) where N
    view = @views(getcontents(x.data)[1:n,:])
    TimeSlices{N,1}(MetaArray(SignalTrait(x.data),view))
end
function Base.Iterators.drop(x::TimeSlices{N,1},n::Integer) where N
    view = @views(getcontents(x.data)[n+1:end,:])
    TimeSlices{N,1}(MetaArray(SignalTrait(x.data),view))
end
function Base.Iterators.take(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,1:n])
    TimeSlices{N,2}(MetaArray(SignalTrait(x.data),view))
end
function Base.Iterators.drop(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,n+1:end])
    TimeSlices{N,2}(MetaArray(SignalTrait(x.data),view))
end
Base.eltype(::Type{<:TimeSlices{N,D,A}}) where {N,D,A} = NTuple{N,eltype(A)}
Base.Iterators.IteratorSize(::Type{<:TimeSlices}) = Iterators.HasLength()
Base.length(x::TimeSlices{<:Any,D}) where D = size(x.data,D)
Base.Iterators.IteratorEltype(::Type{<:TimeSlices}) = Iterators.HasEltype()
