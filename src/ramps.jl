
export RampOn, RampOff, Ramp, FadeTo, sinramp, rampon, rampoff, ramp, fadeto

sinramp(x) = sinpi(0.5x)

struct RampSignal{D,S,Tm,Fn,T} <: WrappedSignal{S,T}
    signal::S
    time::Tm
    fn::Fn
end
function RampSignal(D,signal::S,time::Tm,fn::Fn) where {S,Tm,Fn}

    T = sampletype(signal)
    RampSignal{D,S,Tm,Fn,float(T)}(signal,time,fn)
end

SignalTrait(::Type{T}) where {S,T <: RampSignal{<:Any,S}} =
    SignalTrait(T,SignalTrait(S))
function SignalTrait(::Type{<:RampSignal{D,S,Tm,Fn,T}},::IsSignal{<:Any,Fs,L}) where
    {D,S,Tm,Fn,T,Fs,L}

    IsSignal{T,Fs,L}()
end

child(x::RampSignal) = x.signal
resolvelen(x::RampSignal) = max(1,inframes(Int,maybeseconds(x.time),framerate(x)))

function ToFramerate(
    x::RampSignal{D},
    s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,fs;blocksize) where D

    RampSignal(D,ToFramerate(child(x),fs;blocksize=blocksize),x.time,x.fn)
end
function ToFramerate(
    x::RampSignal{D},
    s::IsSignal{<:Any,Missing},
    __ignore__,fs; blocksize) where D

    RampSignal(D,ToFramerate(child(x),fs;blocksize=blocksize),x.time,x.fn)
end

struct RampBlock{Fn,T}
    Ramp::Fn
    marker::Int
    stop::Int
    offset::Int
    len::Int
end
RampBlock(x,fn,marker,stop,offset,len) =
    RampBlock{typeof(fn),float(sampletype(x))}(fn,marker,stop,offset,len)
nframes(x::RampBlock) = x.len

frame(x::RampSignal{:on},block::RampBlock{Nothing,T},i) where T =
    Fill(one(T),nchannels(x))
frame(x::RampSignal{:off},block::RampBlock{Nothing,T},i) where T =
    Fill(one(T),nchannels(x))
function frame(x::RampSignal{:on},block::RampBlock,i)
    ramplen = block.marker
    rampval = block.Ramp((i+block.offset-1) / ramplen)
    Fill(rampval,nchannels(x))
end
function frame(x::RampSignal{:off},block::RampBlock,i)
    startramp = block.marker - block.offset
    stop = block.stop - block.offset
    rampval = block.stop > startramp ?
        rampval = block.Ramp(1-(i - startramp)/(stop - startramp)) :
        rampval = block.Ramp(1)
    Fill(rampval,nchannels(x))
end

function nextblock(x::RampSignal{:on},maxlen,skip)
    ramplen = resolvelen(x)
    RampBlock(x,x.fn,ramplen,nframes(x),0,min(ramplen,maxlen))
end
function nextblock(x::RampSignal{:off},maxlen,skip)
    rampstart = nframes(x) - resolvelen(x)
    RampBlock(x,nothing,rampstart,nframes(x),0,min(rampstart,maxlen))
end

function nextblock(x::RampSignal{:on},maxlen,skip,block::RampBlock)
    offset = block.offset + block.len
    len = min(nframes(x) - offset,maxlen,block.marker - offset)
    if len == 0
        len = min(nframes(x) - offset,maxlen)
        RampBlock(x,nothing,block.marker,block.stop,offset,len)
    else
        RampBlock(x,x.fn,block.marker,block.stop,offset,len)
    end
end

function nextblock(x::RampSignal{:on},maxlen,skip,block::RampBlock{Nothing})
    offset = block.offset + block.len
    len = min(nframes(x) - offset,maxlen,block.stop - offset)
    if len > 0
        RampBlock(x,nothing,block.marker,block.stop,offset,len)
    end
end

function nextblock(x::RampSignal{:off},maxlen,skip,block::RampBlock{Nothing})
    offset = block.offset + block.len
    len = min(nframes(x) - offset,maxlen,block.marker - offset)
    if len == 0
        len = min(nframes(x) - offset,maxlen)
        RampBlock(x,x.fn,block.marker,block.stop,offset,len)
    else
        RampBlock(x,nothing,block.marker,block.stop,offset,len)
    end
end

function nextblock(x::RampSignal{:off},maxlen,skip,block::RampBlock)
    offset = block.offset + block.len
    len = min(nframes(x) - offset,maxlen,block.stop - offset)
    if len > 0
        RampBlock(x,x.fn,block.marker,block.stop,offset,len)
    end
end

function Base.show(io::IO, ::MIME"text/plain",x::RampSignal{D}) where D
    if x.fn isa typeof(sinramp)
        if D == :on
            write(io,"RampOnFn(",string(x.time),")")
        elseif D == :off
            write(io,"RampOffFn(",string(x.time),")")
        else
            error("Reached unexpected code")
        end
    else
        if D == :on
            write(io,"RampOnFn(",string(x.time),",",string(x.fn),")")
        elseif D == :off
            write(io,"RampOffFn(",string(x.time),",",string(x.fn),")")
        else
            error("Reached unexpected code")
        end
    end
end

"""

    RampOn(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the onset of a signal, smoothly transitioning from 0 to full amplitude
over the course of `len` seconds.

The function determines the shape of the Ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
RampOn(fun::Function) = RampOn(10ms,fun)
RampOn(len::Number=10ms,fun::Function=sinramp) = x -> RampOn(x,len,fun)
function RampOn(x,len::Number=10ms,fun::Function=sinramp)
    x = Signal(x)
    x |> Amplify(RampSignal(:on,x,len,fun))
end

"""
    rampon(x,[len],[fn])

Equivalent to `sink(RampOn(x,[len],[fn]))`

## See also

[`RampOn`](@ref)

"""
rampon(args...) = sink(RampOn(args...))


"""

    RampOff(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the offset of a signal, smoothly transitioning from full amplitude to 0
amplitude over the course of `len` seconds.

The function determines the shape of the Ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
RampOff(fun::Function) = RampOff(10ms,fun)
RampOff(len::Number=10ms,fun::Function=sinramp) = x -> RampOff(x,len,fun)
function RampOff(x,len::Number=10ms,fun::Function=sinramp)
    x = Signal(x)
    x |> Amplify(RampSignal(:off,x,len,fun))
end

"""
    rampoff(x,[len],[fn])

Equivalent to `sink(RampOff(x,[len],[fn]))`

## See also

[`RampOff`](@ref)

"""
rampoff(args...) = sink(RampOff(args...))

"""

    Ramp(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the onset and offset of a signal, smoothly transitioning from 0 to full
amplitude over the course of `len` seconds at the start and from full to 0
amplitude over the course of `len` seconds.

The function determines the shape of the Ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
Ramp(fun::Function) = Ramp(10ms,fun)
Ramp(len::Number=10ms,fun::Function=sinramp) = x -> Ramp(x,len,fun)
function Ramp(x,len::Number=10ms,fun::Function=sinramp)
    x = Signal(x)
    x |> RampOn(len,fun) |> RampOff(len,fun)
end

"""
    ramp(x,[len],[fn])

Equivalent to `sink(Ramp(x,[len],[fn]))`

## See also

[`Ramp`](@ref)

"""
ramp(args...) = sink(Ramp(args...))

"""

    FadeTo(x,y,[len=10ms],[fn=x->sinpi(0.5x)])

Append x to y, with a smooth transition lasting `len` seconds fading from
`x` to `y` (so the total length is `duration(x) + duration(y) - len`).

This fade is accomplished with a [`RampOff`](@ref) of `x` and a
[`RampOn`](@ref) for `y`. `fn` should be non-decreasing with a range of [0,1]
over the domain [0,1]. It should map over the entire range: that is
`fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
FadeTo(y,fun::Function) = FadeTo(y,10ms,fun)
FadeTo(y,len::Number=10ms,fun::Function=sinramp) = x -> FadeTo(x,y,len,fun)
function FadeTo(x,y,len::Number=10ms,fun::Function=sinramp)
    x,y = Uniform((x,y))
    x = Signal(x)
    if ismissing(framerate(x))
        error("Unknown frame rate is not supported by `FadeTo`.")
    end
    n = inframes(Int,maybeseconds(len),framerate(x))
    silence = Signal(zero(sampletype(y))) |> Until((nframes(x) - n)*frames)
    x |> RampOff(len,fun) |> Mix(
        y |> RampOn(len,fun) |> Prepend(silence))
end

"""
    fadeto(x,y,[len],[fn])

Equivalent to `sink(FadeTo(x,[len],[fn]))`

## See also

[`FadeTo`](@ref)

"""
fadeto(args...) = sink(FadeTo(args...))
