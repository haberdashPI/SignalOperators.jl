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
struct PaddedSignal{S,T} <: WrappedSignal
    x::S
    pad::T
end
pad(p) = x -> pad(x,p)
pad(x,p) = isinf(signal_length(x)) ? x : PaddedSignal(x,p)
Base.length(x::PaddedSignal,::IsSignal) = infinite_length
usepad(pad::Number,itr) = pad
usepad(pad::Function,itr) = usepad(pad,IteratorEltype(itr),itr)
usepad(padfn,::Iterators.HasEltype,itr) = padfn(eltype(itr))
usepad(padfn,::Iterators.EltypeUnknown,itr) = padfn(Int)
childsignal(x::PaddedSignal) = x.x

struct UsePad
end
const use_pad = UsePad()

function padresult(x,smp,result)
    if isnothing(result)
        usepad(x.pad,smp), (smp, use_pad)
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
    usepad(x.pad,smp), (smp, use_pad)
Base.iterate(x::PaddedSignal,(smp,state)) = 
    padresult(x,smp,iterate(smp,state))