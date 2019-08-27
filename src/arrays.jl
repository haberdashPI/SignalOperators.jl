
# signals can be arrays with some metadata
function signal(x::AbstractArray,fs) 
    if !(1 ≤ ndims(x) ≤ 2)
        error("To treat an array as a signal it must have 1 or 2 dimensions")
    end
    MetaArray(IsSignal(inHz(fs)),x)
end
SignalTrait(x::MetaArray{<:Any,IsSignal}) = getmeta(x)

struct TimeSlices{N,A <: AbstractArray}
    data::A
end
TimeSlices{N}(x::A) where{N,A} = TimeSlices{N,A}(x)
samples(x::MetaArray{<:Any,IsSignal},::IsSignal) = TimeSlices{size(x,2)}(x)

function Base.iterate(x::TimeSlices,i=1)
    i ≤ size(x.data,1) ? (Tuple(view(x,i,:)), i+1) : nothing
end
function Base.Iterators.take(x::TimeSlices{N},n) where N
    TimeSlices{N}(@views(x[1:n,:]))
end
function Base.Iterators.drop(x::TimeSlices{N},n) where N
    TimeSlices{N}(@views(x[n+1:end,:]))
end
Base.IteratorEltype(::Type{<:TimeSlices}) = Iterators.HasEltype()
Base.eltype(::TimeSlices{N,A}) where {N,A} = NTuple{N,eltype(A)}
Base.IteratorSize(::Type{<:TimeSlices}) = Iterators.HasLength()
Base.length(x::TimeSlices) = length(x.data)

