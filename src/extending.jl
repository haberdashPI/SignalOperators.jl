export append, prepend, pad

################################################################################
# appending signals

struct AppendSignals{Si,Rst,T,L} <: WrappedSignal{Si,T}
    first::Si
    rest::Rst
    len::L
end
SignalTrait(x::Type{T}) where T <: AppendSignals =
    SignalTrait(x,SignalTrait(T))
function SignalTrait(x::Type{<:AppendSignals{Si,Rst,T,L}},
        ::IsSignal{T,Fs}) where {Si,Rst,T,L,Fs}
    SignalTrait{T,Fs,L}()
end
childsignal(x::AppendSignals) = x.xs[1]
nsamples(x::AppendSignals,::IsSignal) = x.len

append(y) = x -> append(x,y)
prepend(x) = y -> append(x,y)
function append(xs...)
    if any(infsignal,xs[1:end-1])
        error("Cannot append to the end of an infinite signal")
    end
    xs = uniform(xs,channels=true) 
    El = promote_type(channel_eltype.(xs)...)
    xs = mapsignal.(x -> convert(El,x),xs)
    len = infsignal(xs[end]) ? nothing : sum(nsamples,xs)
    AppendSignals(xs[1], xs[2:end], len, samplerate(xs))
end
samples(x::AppendSignals,::IsSignal) = Iterators.flatten((x.first,x.rest...))
tosamplerate(x::AppendSignals,s::IsSignal,c::ComputedSignal,fs) = 
    append(tosamplerate(x.first,fs),tosamplerate.(x.rest,fs)...)

################################################################################
# padding
struct PaddedSignal{S,T} <: WrappedSignal{S,T}
    x::S
    pad::T
end
SignalTrait(x::Type{T}) where T <: PaddedSignal = SignalTrait(x,SignalTrait(T))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs,L}) =
    SignalTrait{T,Fs,Nothing}()
nsamples(x::PaddedSignal) = nothing
tosamplerate(x::PaddedSignal,s::IsSignal,c::ComputedSignal,fs) =
    PaddedSignal(tosamplerate(x.x,fs),x.pad)

pad(p) = x -> pad(x,p)
function pad(x,p) 
    x = signal(x)
    infsignal(x) ? x : PaddedSignal(x,p)
end

usepad(x::PaddedSignal) = usepad(x,SignalTrait(x))
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{1,<:Any}}) = (usepad(x,s,x.pad),)
function usepad(x::PaddedSignal,s::IsSignal{NTuple{2,<:Any}})
    v = usepad(x,s,x.pad)
    (v,v)
end
function usepad(x::PaddedSignal,s::IsSignal{<:NTuple{N,<:Any}}) where N
    v = usepad(x,s,x.pad)
    tuple((v for _ in 1:N)...)
end

usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},p::Number) where T = 
    convert(T,p)
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},fn::Function) where T = 
    fn(T)

childsignal(x::PaddedSignal) = x.x

struct UsePad
end
const use_pad = UsePad()

function padresult(x,smp,result)
    if isnothing(result)
        usepad(x), (smp, use_pad)
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
    usepad(x), (smp, use_pad)
Base.iterate(x::PaddedSignal,(smp,state)) = 
    padresult(x,smp,iterate(smp,state))