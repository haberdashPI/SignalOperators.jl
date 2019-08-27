
abstract type WrappedSignal
end
"""
    child_signal(x)

Retriev the signal wrapped by x of type `WrappedSignal`
"""
function child_signal
end
function itersetup(x::WrappedSignal)
    itr = samples(child_signal(x))
    state = iterate(itr)
    itr, state
end

################################################################################
# cutting signals

struct ItrApply{S,A,Fn} <: WrappedSignal
    signal::S
    time::A
    fn::Fn
end
SignalTrait(x::ItrApply) = SignalTrait(x.signal)

const TakeApply{S,A} = ItrApply{S,A,typeof(Iterators.take)}
until(time) = x -> until(x,time)
function until(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.take)
end

const DropApply{S,A} = ItrApply{S,A,typeof(Iterators.drop)}
after(time) = x -> after(x,time)
function after(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.drop)
end

function itersetup(x::IterApply)
    itr = x.fn(samples(x.signal),x.time)
    state = iterate(itr)
    itr, state
end

function Base.iterate(x::ItrApply,(itr,state) = itersetup(x))
    if !isnothing(state)
        val, state = iterate(itr,state)
        val, (itr, state)
    end
end

function signal_length(x::DropApply)
    len = nframes(x.signal_length)
    isinf(len) ? len : len - x.time
end
signal_length(x::TakeApply) = x.time
