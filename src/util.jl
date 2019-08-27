using Statistics

zero_helper(sig) = zero_helper(eltype(sig),length(sig))
zero_helper(x::NTuple{M,T},N) where {M,T} = zeros(T,N,M)

asarray(x::AbstractArray) = x
asarray(x) = asarray(x,SignalTrait(x))
function asarray(x,s::IsSignal) 
    smp = samples(x)
    asarray(x,s,smp,IteratorSize(x))
end
asarray(x, ::Nothing) = error("Don't know how to interpret value as an array: $x")
function asarray(xs,::IsSignal,smp,::HasLength)
    result = zero_helper(smp)
    samples_to_result!(result,smp)
end
function samples_to_result!(result,smp)
    @simd for (i,x) in enumerate(smp)
        result[i,:] .= x
    end
    result
end
function asarray(x,::IsSignal,smp,::IsInfinite)
    error("Cannot store infinite signal in an array. (Use `until`?)")
end

abstract type WrappedSignal
end

"""
    child_signal(x)

Retrieve the signal wrapped by x of type `WrappedSignal`
"""
function childsignal
end
function itersetup(x::WrappedSignal)
    itr = samples(childsignal(x))
    state = iterate(itr)
    itr, state
end
