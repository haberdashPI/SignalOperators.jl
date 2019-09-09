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

SignalTrait(::Type{T}) where {Si,T <: ItrApply{Si}} =
    SignalTrait(T,SignalTrait(Si))
function SignalTrait(::Type{<:ItrApply{Si,Tm,Fn}},::IsSignal{T,Fs,L}) where
    {Si,Tm,Fn,T,Fs,L}

    if Fs <: Missing
        IsSignal{T,Missing,Missing}()
    elseif Fn <: typeof(Iterators.take)
        IsSignal{T,Float64,Int}()
    elseif Fn <: typeof(drop_)
        IsSignal{T,Float64,L}()
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

function tosamplerate(x::TakeApply,s::IsSignal,c::ComputedSignal,fs;blocksize)
    ItrApply(tosamplerate(childsignal(x),s,c,fs;blocksize=blocksize),x.time,x.fn)
end

struct DropCheckpoint{C}
    n::Int
    diff::Int
    child::C
end
function checkpoints(x::DropApply,offset,len)
    n = resolvelen(x)
    children = checkpoints(x.signal,offset+n,len)
    map(children) do child
        DropCheckpoint(checkindex(child)-n,n,child)
    end
end
checkpoints(x::TakeApply,offset,len) = checkpoints(x.signal,offset,len)

function sampleat!(result,x::DropApply,sig::IsSignal,i,j,check)
    sampleat!(result,x.signal,SignalTrait(x.signal),i,j-check.diff,check.child)
end

function sampleat!(result,x::TakeApply,sig::IsSignal,i,j,check)
    sampleat!(result,x.signal,SignalTrait(x.signal),i,j,check)
end