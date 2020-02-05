export Until, After, until, after, Window, window

################################################################################
# cutting signals

struct CutApply{Si,Tm,K,T} <: WrappedSignal{Si,T}
    signal::Si
    time::Tm
end
CutApply(signal::T,time,fn) where T = CutApply(signal,SignalTrait(T),time,fn)
CutApply(signal::Si,::IsSignal{T},time::Tm,kind::K) where {Si,Tm,K,T} =
    CutApply{Si,Tm,K,T}(signal,time)
CutMethod(x::CutApply) = CutMethod(x.signal)

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
       isnothing(from) != isnothing(to) ||
       isnothing(at) == isnothing(from)

       error("`Window` must either use the two keywords `at` and `width` OR",
              "the two keywords `from` and `to`.")
    end

    after,until = isnothing(from) ? (at-width/2,width) : from,to-from
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

!!! note

    If you use `frames` as the unit here, keep in mind that
    because this returns all frames *after* the given index,
    the result is effectively zero indexed:
    i.e. `all(sink(After(1:10,1frames)) .== 2:10)`

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

function nframes_helper(x::UntilApply)
    if ismissing(nframes_helper(x.signal)) && resolvelen(x) == 0
        # missing values must still be positive, so a 0 length cut has a known
        # length even if the underlying signal is an unknown length
        return 0
    else
        min(nframes_helper(x.signal),max(0,resolvelen(x)))
    end
end
duration(x::UntilApply) =
    min(duration(x.signal),max(0,inseconds(Float64,maybeseconds(x.time),framerate(x))))

nframes_helper(x::AfterApply) = clamp(nframes_helper(x.signal) - resolvelen(x),0,nframes_helper(x.signal))
duration(x::AfterApply) =
    clamp(duration(x.signal) - inseconds(Float64,maybeseconds(x.time),framerate(x)),0,duration(x.signal))

EvalTrait(x::AfterApply) = DataSignal()

stretchtime(t,scale) = t
stretchtime(t::FrameQuant,scale::Number) = inframes(Int,t*scale)*frames
function ToFramerate(x::UntilApply,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    t = stretchtime(x.time,fs/framerate(x))
    CutApply(ToFramerate(child(x),fs;blocksize=blocksize),t,
        Val{:Until}())
end
function ToFramerate(x::CutApply{<:Any,<:Any,K},s::IsSignal{<:Any,Missing},
    __ignore__,fs; blocksize) where K

    t = stretchtime(x.time,fs/framerate(x))
    CutApply(ToFramerate(child(x),fs;blocksize=blocksize),t,K())
end

struct CutBlock{C}
    n::Int
    child::C
end
child(x::CutBlock) = x.child

function nextblock(x::AfterApply,maxlen,skip)
    if resolvelen(x) == 0
        childblock = nextblock(child(x),maxlen,false)
        CutBlock(0,childblock)
    else
        len = max(0,resolvelen(x))
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
end
function nextblock(x::AfterApply,maxlen,skip,block::CutBlock)
    childblock = nextblock(child(x),maxlen,skip,child(block))
    if !isnothing(childblock)
        CutBlock(0,childblock)
    end
end
nextblock(x::AfterApply,maxlen,skip,block::CutBlock{Nothing}) = nothing
function timeslice(x::AfterApply,indices)
    from = clamp(resolvelen(x),0,nframes(x.signal))+1
    to = nframes(x.signal)
    timeslice(x.signal,(from:to)[indices])
end

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
function timeslice(x::UntilApply,indices)
    to = clamp(resolvelen(x),0,nframes(x.signal))
    timeslice(x.signal,(1:to)[indices])
end

nframes(x::CutBlock) = nframes(child(x))
nframes(x::CutBlock{Nothing}) = 0
@Base.propagate_inbounds frame(x::CutApply,block::CutBlock,i) =
    frame(child(x),child(block),i)