export until, after

################################################################################
# cutting signals

struct ItrApply{S,Fn} <: WrappedSignal{S}
    signal::S
    time::Int
    fn::Fn
end
childsignal(x::ItrApply) = x.signal
SignalTrait(x::ItrApply) = SignalTrait(x.signal)

function wrapresult(smp, result)
    if !isnothing(result)
        val, state = result
        val, (smp, state)
    end
end

function Base.iterate(x::ItrApply)
    smp = x.fn(samples(x.signal),x.time)
    wrapresult(smp,iterate(smp))
end
Base.iterate(x::ItrApply,(smp,state)) = wrapresult(smp, iterate(smp,state))
       
const TakeApply{S} = ItrApply{S,typeof(Iterators.take)}
until(time) = x -> until(x,time)
function until(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.take)
end
Base.Iterators.IteratorSize(::Type{<:TakeApply}) = Iterators.HasLength()

const DropApply{S} = ItrApply{S,typeof(Iterators.drop)}
after(time) = x -> after(x,time)
function after(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),Iterators.drop)
end

# TODO fix this, need to elikminate signal_length
function Base.length(x::TakeApply)
    take = x.time
    if infsignal(x.signal)
        take
    else
        min(nsamples(x.signal),take)
    end
end

function Base.length(x::DropApply)
    drop = x.time
    if infsignal(x.signal)
        error("Infinite signal!")
    else
        (min(nsamples(x.signal)) - drop)
    end
end