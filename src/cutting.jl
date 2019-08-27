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
Base.IteratorSize(::Type{<:TakeApply}) = Iterators.HasLength()

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

# TODO fix this, need to elikminate signal_length
function length(x::TakeApply)
    take = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    min(len,take)
end

function length(x::DropApply)
    drop = x.time
    len = inframes(Int,signal_length(x.signal),samplerate(x))
    (len - drop)
end