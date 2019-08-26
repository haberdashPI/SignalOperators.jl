using Statistics

zero_helper(sig) = zero_helper(eltype(sig),length(sig))
zero_helper(x::NTuple{M,T},N) where {M,T} = zeros(T,N,M)

asarray(x::AbstractArray) = x
asarray(x) = asarray(x,SignalTrait(x))
asarray(x,s::IsSignal) = asarray(x,s,IteratorSize(samples(x)))
asarray(x, ::Nothing) = error("Don't know how to interpret value as an array: $x")
function asarray(x,::IsSignal,::HasLength)
    sig = samples(x)
    result = zero_helper(sig)
    @simd for (i,x) in enumerate(sig)
        result[i,:] .= x
    end
    result
end
function asarray(x,::IsSignal,::IsInfinite)
    error("Cannot store infinite signal in an array. (Use `until`?)")
end