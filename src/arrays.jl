export sink
using MetaArrays

# signals can be arrays with some metadata
function signal(x::AbstractArray,fs) 
    if !(1 ≤ ndims(x) ≤ 2)
        error("To treat an array as a signal it must have 1 or 2 dimensions")
    end
    MetaArray(IsSignal{NTuple{size(x,2),eltype(x)}}(inHz(fs)),x)
end
SignalTrait(x::MetaArray{<:Any,<:IsSignal}) = getmeta(x)
signal_eltype(::Type{<:MetaArray{<:Any,<:IsSignal{T}}}) where T = T

struct TimeSlices{N,D,A <: AbstractArray} 
    data::A
end
TimeSlices{N}(x::A) where{N,A} = TimeSlices{N,1,A}(x)
TimeSlices{N,D}(x::A) where{N,D,A} = TimeSlices{N,D,A}(x)
samples(x::MetaArray{<:Any,<:IsSignal},::IsSignal) = TimeSlices{size(x,2)}(x)

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
    TimeSlices{N,2}(MetaArray(SignalTrait(x.data),view))
end
function Base.Iterators.take(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,1:n])
    TimeSlices{N,1}(MetaArray(SignalTrait(x.data),view))
end
function Base.Iterators.drop(x::TimeSlices{N,2},n::Integer) where N
    view = @views(getcontents(x.data)[:,n+1:end])
    TimeSlices{N,2}(MetaArray(SignalTrait(x.data),view))
end
Base.eltype(::Type{<:TimeSlices{N,D,A}}) where {N,D,A} = NTuple{N,eltype(A)}
Base.Iterators.IteratorSize(::Type{<:TimeSlices}) = Iterators.HasLength()
Base.length(x::TimeSlices) = length(x.data)
Base.Iterators.IteratorEltype(::Type{<:TimeSlices}) = Iterators.HasEltype()
