using MetaArrays

# signals can be arrays with some metadata
function signal(x::AbstractArray,fs) 
    if !(1 ≤ ndims(x) ≤ 2)
        error("To treat an array as a signal it must have 1 or 2 dimensions")
    end
    MetaArray(IsSignal{NTuple{size(x,2),eltype(x)}}(inHz(fs)),x)
end
SignalTrait(x::MetaArray{<:Any,IsSignal}) = getmeta(x)

struct TimeSlices{N,D,A <: AbstractArray} 
    data::A
end
TimeSlices{N}(x::A) where{N,A} = TimeSlices{N,1,A}(x)
TimeSlices{N,D}(x::A) where{N,D,A} = TimeSlices{N,D,A}(x)
samples(x::MetaArray{<:Any,IsSignal},::IsSignal) = TimeSlices{size(x,2)}(x)

Base.iterate(x::TimeSlices{<:Any,1},i=1) =
    i ≤ size(x.data,1) ? (Tuple(view(x,i,:)), i+1) : nothing
Base.iterate(x::TimeSlices{<:Any,2},i=1)   
    i ≤ size(x.data,2) ? (Tuple(view(x,:,i)), i+1) : nothing

Base.Iterators.take(x::TimeSlices{N,1},n) where N =
    TimeSlices{N,1}(@views(x[1:n,:]))
Base.Iterators.drop(x::TimeSlices{N,1},n) where N =
    TimeSlices{N,2}(@views(x[n+1:end,:]))
Base.Iterators.take(x::TimeSlices{N,2},n) where N =
    TimeSlices{N,1}(@views(x[:,1:n]))
Base.Iterators.drop(x::TimeSlices{N,2},n) where N =
    TimeSlices{N,2}(@views(x[:,n+1:end]))
Base.IteratorEltype(::Type{<:TimeSlices}) = Iterators.HasEltype()
Base.eltype(::TimeSlices{N,D,A}) where {N,D,A} = NTuple{N,eltype(A)}
Base.IteratorSize(::Type{<:TimeSlices}) = Iterators.HasLength()
Base.length(x::TimeSlices) = length(x.data)