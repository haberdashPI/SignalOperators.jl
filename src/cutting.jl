export until, after

################################################################################
# cutting signals

struct ItrApply{S,Fn} <: WrappedSignal
    signal::S
    time::Int
    fn::Fn
end
childsignal(x::ItrApply) = x.signal
SignalTrait(x::ItrApply) = SignalTrait(x.signal)

const TakeApply{S} = ItrApply{S,typeof(Iterators.take)}
until(time) = x -> until(x,time)
function until(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.take)
end

const DropApply{S} = ItrApply{S,typeof(Iterators.drop)}
after(time) = x -> after(x,time)
function after(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.drop)
end

function itersetup(x::ItrApply)
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

function signal_length(x::TakeApply,::IsSignal)
    take = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    min(len,take)*frames 
end

function nsamples(x::TakeApply,::IsSignal)
    take = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    min(len,take)
end

function signal_length(x::DropApply,::IsSignal)
    drop = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    (len - drop)*frames
end

function nsamples(x::DropApply,::IsSignal)
    drop = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    (len - drop)
end