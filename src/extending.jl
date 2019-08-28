export append, prepend, pad

################################################################################
# appending signals

append(y) = x -> append(x,y)
prepend(x) = y -> prepend(x,y)
function append(xs...)
    Iterators.flatten(samples.(uniform.(xs,channels=true)))
end

################################################################################
# padding
struct PaddedSignal{S,T} <: WrappedSignal{S}
    x::S
    pad::T
end
pad(p) = x -> pad(x,p)
pad(x,p) = infsignal(x) ? x : PaddedSignal(x,p)
Base.length(x::PaddedSignal,::IsSignal) = infinite_length

usepad(x::PaddedSignal) = usepad(x,SignalTrait(x))
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{1,<:Any}}) = (usepad(x,s,x.pad),)
function usepad(x::PaddedSignal,s::IsSignal{NTuple{2,<:Any}})
    v = usepad(x,s,x.pad)
    (v,v)
end
function usepad(x::PaddedSignal,s::IsSignal{<:NTuple{N,<:Any}}) where N
    v = usepad(x,s,x.pad)
    tuple((v for _ in 1:N)...)
end

usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},p::Number) where T = 
    convert(T,p)
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},fn::Function) where T = 
    fn(T)

childsignal(x::PaddedSignal) = x.x

struct UsePad
end
const use_pad = UsePad()

function padresult(x,smp,result)
    if isnothing(result)
        usepad(x), (smp, use_pad)
    else
        val, state = result
        val, (smp, state)
    end
end

function Base.iterate(x::PaddedSignal)
    smp = samples(x.x)
    padresult(x,smp,iterate(smp))
end
Base.iterate(x::PaddedSignal,(smp,state)::Tuple{<:Any,UsePad}) = 
    usepad(x), (smp, use_pad)
Base.iterate(x::PaddedSignal,(smp,state)) = 
    padresult(x,smp,iterate(smp,state))