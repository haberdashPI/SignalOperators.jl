export until, after

################################################################################
# cutting signals

struct CutApply{Si,Tm,K,T} <: WrappedSignal{Si,T}
    signal::Si
    time::Tm
end
CutApply(signal::T,time,fn) where T = CutApply(signal,SignalTrait(T),time,fn)
CutApply(signal::Si,::IsSignal{T},time::Tm,kind::K) where {Si,Tm,K,T} =
    CutApply{Si,Tm,K,T}(signal,time)

SignalTrait(::Type{T}) where {Si,T <: CutApply{Si}} =
    SignalTrait(T,SignalTrait(Si))
function SignalTrait(::Type{<:CutApply{Si,Tm,K}},::IsSignal{T,Fs,L}) where
    {Si,Tm,K,T,Fs,L}

    if Fs <: Missing
        IsSignal{T,Missing,Missing}()
    elseif K <: Val{:until}
        IsSignal{T,Float64,Int}()
    elseif K <: Val{:after}
        IsSignal{T,Float64,L}()
    else
        error("Unexpected cut apply type $K")
    end
end

child(x::CutApply) = x.signal
resolvelen(x::CutApply) = inframes(Int,maybeseconds(x.time),framerate(x))

const UntilApply{S,T} = CutApply{S,T,Val{:until}}
const AfterApply{S,T} = CutApply{S,T,Val{:after}}

"""
    until(x,time)

Create a signal of all frames of `x` up until and including `time`.
"""
until(time) = x -> until(x,time)
until(x,time) = CutApply(signal(x),time,Val{:until}())

"""
    after(x,time)

Create a signal of all frames of `x` after `time`.
"""
after(time) = x -> after(x,time)
after(x,time) = CutApply(signal(x),time,Val{:after}())

Base.show(io::IO,::MIME"text/plain",x::CutApply) = pprint(io,x)
function PrettyPrinting.tile(x::CutApply)
    operate = literal(string(cutname(x),"(",(x.time),")"))
    tilepipe(signaltile(x.signal),operate)
end
signaltile(x::CutApply) = PrettyPrinting.tile(x)

cutname(x::UntilApply) = "until"
cutname(x::AfterApply) = "after"

nframes(x::UntilApply) = min(nframes(x.signal),resolvelen(x))
duration(x::UntilApply) =
    min(duration(x.signal),inseconds(Float64,maybeseconds(x.time),framerate(x)))

nframes(x::AfterApply) = max(0,nframes(x.signal) - resolvelen(x))
duration(x::AfterApply) =
    max(0,duration(x.signal) - inseconds(Float64,maybeseconds(x.time),framerate(x)))

EvalTrait(x::AfterApply) = DataSignal()
function toframerate(x::UntilApply,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    CutApply(toframerate(child(x),fs;blocksize=blocksize),x.time,
        Val{:until}())
end
function toframerate(x::CutApply{<:Any,<:Any,K},s::IsSignal{<:Any,Missing},
    __ignore__,fs; blocksize) where K

    CutApply(toframerate(child(x),fs;blocksize=blocksize),x.time,K())
end

struct CutBlock{C}
    n::Int
    child::C
end
child(x::CutBlock) = x.child

function nextblock(x::AfterApply,maxlen,skip)
    len = resolvelen(x)
    childblock = nextblock(child(x),len,true)
    skipped = nframes(childblock)
    while !isnothing(childblock) && skipped < len
        childblock = nextblock(child(x),min(maxlen,len - skipped),true,
            childblock)
        isnothing(childblock) && break
        skipped += nframes(childblock)
    end
    if skipped < len
        io = IOBuffer()
        signalshow(io,child(x))
        sig_string = String(take!(io))

        error("Signal is too short to skip $(maybeseconds(x.time)): ",
            sig_string)
    end
    @assert skipped == len
    nextblock(x,maxlen,skip,CutBlock(0,childblock))
end
function nextblock(x::AfterApply,maxlen,skip,block::CutBlock)
    childblock = nextblock(child(x),maxlen,skip,child(block))
    if !isnothing(childblock)
        CutBlock(0,childblock)
    end
end
nextblock(x::AfterApply,maxlen,skip,block::CutBlock{Nothing}) = nothing

initblock(x::UntilApply) = CutBlock(resolvelen(x),nothing)
function nextblock(x::UntilApply,len,skip,block::CutBlock=initblock(x))
    nextlen = block.n - nframes(block)
    if nextlen > 0
        childblock = !isnothing(child(block)) ?
            nextblock(child(x),min(nextlen,len),skip,child(block)) :
            nextblock(child(x),min(nextlen,len),skip)
        if !isnothing(childblock)
            CutBlock(nextlen,childblock)
        end
    end
end

nframes(x::CutBlock) = nframes(child(x))
nframes(x::CutBlock{Nothing}) = 0
@Base.propagate_inbounds frame(x::CutApply,block::CutBlock,i) =
    frame(child(x),child(block),i)