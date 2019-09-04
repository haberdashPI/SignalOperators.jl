export append, prepend, pad

################################################################################
# appending signals

struct AppendSignals{Si,All,T,L} <: WrappedSignal{Si,T}
    first::Si
    all::All
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
    AppendSignals(xs[1], xs, len, samplerate(xs))
end
tosamplerate(x::AppendSignals,s::IsSignal,c::ComputedSignal,fs) = 
    append(tosamplerate(x.first,fs),tosamplerate.(x.rest,fs)...)

struct AppendCheckpoint <: AbstractCheckpoint
    n::Int
    sig_index::Int
end
cindex(x::AppendCheckpoint) = x.n
sink_checkpoints(x::AppendSignals,n) = 
    enumerate([1;cumsum(nsamples.(x.all[1:end-1])).+1]) |> 
    @λ(map(((i,cum)) -> AppendCheckpoint(cum,i),_)) |>
    @λ(filter(@λ(cindex(_) < n),_))
function sample_init(x::AppendSignals)
    (sig_index=1,offset=0,child=sample_init(childsignal(x)))
end
function sampleat!(result,x,sig,i,j,data)
    sampleat!(result,x.all[data.sig_index],i,j+data.offset,data.child)
end
function oncheckpoint(x::AppendSignals,check::AppendCheckpoint,data)
    (sig_index=check.sig_index,offset=-check.n+1,child=data.child)
end
function oncheckpoint(x::AppendSignals,check,data)
    oncheckpoint(childsignal(x),check,data)
end

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
block_length(x::PaddedSignal) = Block()

function sinkblock!(result,x::PaddedSignal,::IsSignal,data,offset::Number,
    block::Block)

    until = min(offset+size(result,1),nsamples(x.x)) - offset
    if until ≥ 1
        sinkblock!(@view(result[1:until,:]),x.x,SignalTrait(x.x),data,offset,
            block_length(x.x))
    end
    if until < size(result,1)
        result[max(1,until+1):end,:] .= usepad(x)
    end
end



    
