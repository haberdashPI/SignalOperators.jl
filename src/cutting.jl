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
    ItrApply(x,inframes(Int,maybeseconds(time),samplerate(x)),Iterators.take)
end
Base.Iterators.IteratorSize(::Type{<:TakeApply}) = Iterators.HasLength()

drop_(x,n) = Iterators.drop(x,n)
drop_(x::WrappedSignal,n) = drop_(childsignal(x),n)
const DropApply{S} = ItrApply{S,typeof(drop_)}
drop_(x::DropApply,n) = drop_(childsignal(x),x.time+n)
drop_(x::TakeApply,n) = Iterators.take(drop_(childsignal(x),n),x.time - n)
after(time) = x -> after(x,time)
function after(x,time)
    ItrApply(x,inframes(Int,time,samplerate(x)),drop_)
end
Base.Iterators.IteratorSize(::Type{<:DropApply{S}}) where S = 
    Iterators.IteratorSize(S) isa Iterators.IsInfinite ? 
    Iterators.IsInfinite() :
    Iterators.HasLength()

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