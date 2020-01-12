export Until, After, until, after

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
    elseif K <: Val{:Until}
        IsSignal{T,Float64,Int}()
    elseif K <: Val{:After}
        IsSignal{T,Float64,L}()
    else
        error("Unexpected cut apply type $K")
    end
end

child(x::CutApply) = x.signal
resolvelen(x::CutApply) = inframes(Int,maybeseconds(x.time),framerate(x))

const UntilApply{S,T} = CutApply{S,T,Val{:Until}}
const AfterApply{S,T} = CutApply{S,T,Val{:After}}

"""
    Window(x;from,to)
    Window(x;at,width)

Extract a window of time from a signal by specifying either the start and stop
point of the window (`from` and `to`) or the center and width (`at` and `wdith`)
of the window.
"""
Window(;kwds...) = x -> Window(x;kwds...)
function Window(x;at=nothing,width=nothing,from=nothing,to=nothing)
    if isnothing(at) != isnothing(width) ||
       isnothing(from) !=  isnothing(to) ||
       isnothing(at) == isnothing(from)

       error("`Window` must either use the two keywords `at` and `width` OR",
              "the two keywords `from` and `to`.")
    end

    after,until = isnothign(from) ? (at-width/2,width) : from,to-from
    x |> After(after) |> Until(until)
end

"""
    window(x;from,to)
    window(x;at,width)

Equivalent to `sink(Window(...))`.

## See also

[`Window`](@ref)

"""
window(x;kwds...) = sink(Window(x;kwds...))

struct WindowIter{Sig,Sink,T}
    x::Sig
    buffer::Sink
    times::T
    N::Int
end

"""
    windows(x,[to];times,width)

Equivalent  to (sink(Window(x,at=t,width=width),to) for t in times)
but more efficient.

## See also

[`Window`](@ref)

"""
function windows(x,to=nothing;times,width)
    x = Signal(x)
    to = isnothing(to) ? refineroot(root(x)) : to
    N = inframes(Int,maybeseconds(width)/2,framerate(x))
    len = min(nframes(x),1+2N)
    buffer = initsink(Until(x,len),to)

    WindowIter(x,buffer,times,N)
end

function iterate(itr::WindowIter,state=nothing)
    oldframe, sinkstate, time, state = if isnothing(state)
        result = iterate(itr.times)
        isnothing(result) && return nothing
        0, nothing, result...
    else
        oldframe, sinkstate, oldstate = state
        result = iterate(oldstate)
        isnothing(result) && return nothing
        oldframe, sinkstate, result...
    end

    frame = inframes(Int,maybeseconds(time),framerate(itr.x))
    # do not recalculate frames that overlap with the old window
    len = 1+2itr.N
    start, C, skip = if frame - oldframe < len
        offset = frame - oldframe - 1
        tocopy = offset - len
        @simd  @inbounds for i in 1:tocopy
            itr.buffer[i] = itr.buffer[offset + i]
        end
        tocopy+1, len - tocopy, 0
    elseif frame - oldframe > len
        1, len, len - (frame-oldframe)
    else
        1, len, 0
    end

    maxlen = min(len,nframes(x)-frame-itr.N)
    sinkstate = if isnothing(sinkstate)
        sink!(view(itr.buffer,start:maxlen,:),x,SignalTrait(x))
    else
        sink!(view(itr.buffer,start:maxlen,:),x,SignalTrait(x),sinkstate)
    end

    itr.buffer, (frame, sinkstate, state)
end

# TOOD: apply to data signals differently

"""
    Until(x,time)

Create a signal of all frames of `x` up until and including `time`.
"""
Until(time) = x -> Until(x,time)
Until(x,time) = CutApply(Signal(x),time,Val{:Until}())

"""
    until(x,time)

Equivalent to `sink(Until(x,time))`

## See also

[`Until`](@ref)

"""
until(x,time) = sink(Until(x,time))

"""
    After(x,time)

Create a signal of all frames of `x` after `time`.
"""
After(time) = x -> After(x,time)
After(x,time) = CutApply(Signal(x),time,Val{:After}())

"""
    after(x,time)

Equivalent to `sink(After(x,time))`

## See also

[`After`](@ref)

"""
after(x,time) = sink(After(x,time))

Base.show(io::IO,::MIME"text/plain",x::CutApply) = pprint(io,x)
function PrettyPrinting.tile(x::CutApply)
    operate = literal(string(cutname(x),"(",(x.time),")"))
    tilepipe(signaltile(x.signal),operate)
end
signaltile(x::CutApply) = PrettyPrinting.tile(x)

cutname(x::UntilApply) = "Until"
cutname(x::AfterApply) = "After"

nframes(x::UntilApply) = min(nframes(x.signal),resolvelen(x))
duration(x::UntilApply) =
    min(duration(x.signal),inseconds(Float64,maybeseconds(x.time),framerate(x)))

nframes(x::AfterApply) = max(0,nframes(x.signal) - resolvelen(x))
duration(x::AfterApply) =
    max(0,duration(x.signal) - inseconds(Float64,maybeseconds(x.time),framerate(x)))

EvalTrait(x::AfterApply) = DataSignal()
function ToFramerate(x::UntilApply,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    CutApply(ToFramerate(child(x),fs;blocksize=blocksize),x.time,
        Val{:Until}())
end
function ToFramerate(x::CutApply{<:Any,<:Any,K},s::IsSignal{<:Any,Missing},
    __ignore__,fs; blocksize) where K

    CutApply(ToFramerate(child(x),fs;blocksize=blocksize),x.time,K())
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