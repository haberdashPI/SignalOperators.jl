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
signal_length(x::PaddedSignal,::IsSignal) = infinite_length
usepad(pad::Number,itr) = pad
usepad(pad::Function,itr) = usepad(pad,IteratorEltype(itr),itr)
usepad(padfn,::Iterators.HasEltype,itr) = padfn(eltype(itr))
usepad(padfn,::Iterators.EltypeUnknown,itr) = padfn(Int)
childsignal(x::PaddedSignal) = x.x

function Base.iterate(x::PaddedSignal,(itr,state) = itersetup(x))
    if isnothing(state)
        usepad(x.pad,itr), (itr, state)
    else
        (val, state) = iterate(itr,state)
        val, (itr, state)
    end
end