using AxisArrays

# signals can be an AxisArray
function SignalTrait(x::AxisArray)
    times = axisvalues(x,Axis{:time})
    IsSignal(1/step(times))
end
signal_length(x::AxisArray,::IsSignal) = (size(x,Axis{:time})-1)*frames
nsamples(x::AxisArray,::IsSignal) = size(x,Axis{:time})

struct AxisTimeSlices{N,Ax} where {N,Ax <: AxisArray}
    data::Ax
    start::Int
    n::Int
end
AxisTimeSlices{N}(data:Ax,start,n) where {N,Ax <: AxisArray} = 
    AxisTimeSlices{N,Ax}(data,start,n)

function samples(x::AxisArray) 
    if 1 ≤ ndims(x) ≤ 2
        error("Expected AxisArray to have one or two dimensions")
    end
    N = if ndims(x) == 1 
        1
    else
        other = setdiff(1:2,axisdim(x,Axis{:time}))
        size(x,other)
    end

    AxisTimeSlices{N}(x,1,size(x,Axis{:time}))
end
function Base.iterate(x::AxisTimeSlices,i=x.start)
    i ≤ size(x.data,x.n) ? Tuple(selectdim(x,x.n,i)) : nothing
end
function Base.Iterators.take(x::AxisTimeSlices{N},n) where N
   AxisTimeSlices{N}(x,x.start,n)
end
function Base.Iterators.drop(x::AxisTimeSlices{N},n) where N
    AxisTimeSlices{N}(x,x.start,x.start+min(n,(x.n-x.start+1))-1)
end
Base.IteratorEltype(x::AxisTimeSlices) = HasEltype()
Base.eltype(::Type{<:AxisTimeSlices{N,A}}) where {N,A} = NTuple{N,eltype(A)}
Base.IteratorSize(x::AxisTimeSlices) = HasLength()
Base.length(x::AxisTimeSlices) = length(x.data)

function arraych(x::AxisArray)
    other = setdiff(1:2,axisdim(x,Axis{:time}))
    size(x,other)
end
asarray(x::AxisArray) = x
