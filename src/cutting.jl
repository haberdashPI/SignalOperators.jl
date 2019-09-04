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
    {Si,Tm,T,Fs,L}

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

function wrapresult(smp, result)
    if !isnothing(result)
        val, state = result
        val, (smp, state)
    end
end

function Base.iterate(x::ItrApply)
    smp = x.fn(samples(x.signal),resolvelen(x))
    wrapresult(smp,iterate(smp))
end
Base.iterate(x::ItrApply,(smp,state)) = wrapresult(smp, iterate(smp,state))
       
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
Base.Iterators.IteratorSize(::Type{<:DropApply{S}}) where S = 
    Iterators.IteratorSize(S) isa Iterators.IsInfinite ? 
    Iterators.IsInfinite() :
    Iterators.HasLength()

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

@Base.propagate_inbounds function signal_setindex!(result,x::ItrApply,i)
    signal_setindex!(result,childsignal(x),i)
end
group_length(x) = length(x)
signal_indices(x::ItrApply,range::Range) =
    signal_indices(childsignal(x),x.fn(range,resolvelen(x)))
signal_indices(x::ItrApply,groups) =
    signal_indices(childsignal(x),limited_partition(x.fn,groups,resolvelen(x)))
function limited_partition(::typeof(Iterators.drop),groups,limit)
    groups = Array{eltype(groups)}(undef,0)
    n, result = reduce(groups,init=(0,groups)) do ((n,groups),group)
        if n < limit
            new_n = max(limit,n+group_length(group))
        else
            new_n = limit
        end
        if new_n == limit
            k = limit - n
            if k > 0
                new_groups = vcat(groups,Iterators.drop(group,k))
            else
                new_groups = vcat(groups,group)
            end
        else
            new_groups = groups
        end
        (new_n,new_groups)
    end

    result
end
function limited_partition(::typeof(Iterators.take),groups,limit)
    groups = Array{eltype(groups)}(undef,0)
    n, result = reduce(groups,init=(0,groups)) do ((n,groups),group)
        if n < limit
            new_n = max(limit,n+group_length(group))
        else
            new_n = limit
        end
        if new_n == limit
            k = limit - n
            if k > 0
                new_groups = vcat(groups,Iterators.take(group,k))
            else
                new_groups = groups
            end
        else
            new_groups = vcat(groups,group)
        end
        (new_n,new_groups)
    end

    result
end