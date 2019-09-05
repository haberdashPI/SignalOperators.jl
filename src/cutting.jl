export until, after

################################################################################
# cutting signals

struct ItrApply{Si,Tm,Fn,T} <: WrappedSignal{Si,T}
    signal::Si
    time::Tm
    fn::Fn
end
ItrApply(signal::T,time,fn) where T = ItrApply(signal,SignalTrait(T),time,fn)
ItrApply(signal::Si,::IsSignal{T},time::Tm,fn::Fn) where {Si,Tm,Fn,T} = 
    ItrApply{Si,Tm,Fn,T}(signal,time,fn)

function SignalTrait(::Type{<:ItrApply{Si,Tm,Fn}},::IsSignal{T,Fs,L}) where
    {Si,Tm,Fn,T,Fs,L}

    if Fs <: Missing
        SignalTrait{T,Missing,Missing}()
    elseif Fn <: typeof(Iterators.take)
        SignalTrait{T,Float64,Int}()
    elseif Fn <: typeof(drop_)
        SignalTrait{T,Float64,L}()
    end
end
    
childsignal(x::ItrApply) = x.signal
resolvelen(x::ItrApply) = inframes(Int,maybeseconds(x.time),samplerate(x))
       
const TakeApply{S,T} = ItrApply{S,T,typeof(Iterators.take)}
until(time) = x -> until(x,time)
function until(x,time)
    ItrApply(signal(x),time,Iterators.take)
end

drop_(x,n) = Iterators.drop(x,n)
drop_(x::WrappedSignal,n) = drop_(childsignal(x),n)
const DropApply{S,T} = ItrApply{S,T,typeof(drop_)}
drop_(x::DropApply,n) = drop_(childsignal(x),x.time+n)
drop_(x::TakeApply,n) = Iterators.take(drop_(childsignal(x),n),x.time - n)
after(time) = x -> after(x,time)
function after(x,time)
    ItrApply(signal(x),time,drop_)
end

function nsamples(x::TakeApply,::IsSignal)
    take = resolvelen(x)
    if infsignal(x.signal)
        take
    else
        min(nsamples(x.signal),take)
    end
end

function nsamples(x::DropApply,::IsSignal)
    drop = resolvelen(x)
    if infsignal(x.signal)
        error("Infinite signal!")
    else
        (min(nsamples(x.signal)) - drop)
    end
end

function tosamplerate(x::ItrApply,s::IsSignal,c::ComputedSignal,fs)
    tosamplerate(childsignal(x),s,c,fs)
end

@Base.propagate_inbounds function sampleat!(result::AbstractArray,x::DropApply,
    sig::IsSignal,i::Number,j::Number)

    child = childsignal(x)
    sampleat!(result,child,SignalTrait(child),i,j)
end

@Base.propagate_inbounds function sampleat!(result::AbstractArray,x::DropApply,
    sig::IsSignal,i::Number,j::Number)

    child = childsignal(x)
    sampleat!(result,child,SignalTrait(child),i,j+x.n)
end