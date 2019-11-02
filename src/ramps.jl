
export rampon, rampoff, ramp, fadeto, sinramp

sinramp(x) = sinpi(0.5x)

struct RampSignal{D,S,Tm,Fn,T} <: WrappedSignal{S,T}
    signal::S
    time::Tm
    fn::Fn
end
function RampSignal(D,signal::S,time::Tm,fn::Fn) where {S,Tm,Fn}

    T = channel_eltype(signal)
    RampSignal{D,S,Tm,Fn,float(T)}(signal,time,fn)
end

SignalTrait(::Type{T}) where {S,T <: RampSignal{<:Any,S}} =
    SignalTrait(T,SignalTrait(S))
function SignalTrait(::Type{<:RampSignal{D,S,Tm,Fn,T}},::IsSignal{<:Any,Fs,L}) where
    {D,S,Tm,Fn,T,Fs,L}

    IsSignal{T,Fs,L}()
end

child(x::RampSignal) = x.signal
resolvelen(x::RampSignal) = max(1,insamples(Int,maybeseconds(x.time),samplerate(x)))

function tosamplerate(
    x::RampSignal{D},
    s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,fs;blocksize) where D

    RampSignal(D,tosamplerate(child(x),fs;blocksize=blocksize),x.time,x.fn)
end
function tosamplerate(
    x::RampSignal{D},
    s::IsSignal{<:Any,Missing},
    __ignore__,fs; blocksize) where D

    RampSignal(D,tosamplerate(child(x),fs;blocksize=blocksize),x.time,x.fn)
end

struct RampCheckpoint{S,R} <: AbstractCheckpoint{S}
    time::Int
    n::Int
end
checkindex(x::RampCheckpoint) = x.n
function RampCheckpoint(x::RampSignal,len::Int,index::Int,ramp::Bool)
    RampCheckpoint{typeof(x),ramp}(len,index)
end

function atcheckpoint(x::RampSignal{:on},offset::Number,stopat::Int)
    ramplen =  resolvelen(x)
    RampCheckpoint(x,ramplen,offset+1,offset ≤ ramplen)
end
function atcheckpoint(x::S,check::RampCheckpoint{S},stopat::Int) where
    S <: RampSignal{:on}
    ramplen = resolvelen(x)
    if checkindex(check) ≤ resolvelen(x)
        RampCheckpoint(x,ramplen,min(ramplen+1,stopat+1),false)
    else
        RampCheckpoint(x,ramplen,stopat+1,false)
    end
end

function atcheckpoint(x::RampSignal{:off},offset::Number,stopat::Int)
    startramp = nsamples(x) - resolvelen(x)
    RampCheckpoint(x,startramp,offset+1,nsamples(x) ≤ startramp)
end

function atcheckpoint(x::S,check::RampCheckpoint{S},stopat::Int) where
    S <: RampSignal{:off}

    startramp = nsamples(x) - resolvelen(x)
    if checkindex(check) ≥ startramp
        RampCheckpoint(x,startramp,stopat+1,true)
    else
        RampCheckpoint(x,startramp,min(startramp,stopat+1),true)
    end
end


@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::RampCheckpoint{S,false}) where S <: RampSignal
    writesink!(result,i,Fill(one(channel_eltype(x)),nchannels(x)))
end
@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::RampCheckpoint{S,true}) where S <: RampSignal{:off}

    startramp = check.time
    rampval = nsamples(x) > startramp ?
        rampval = x.fn(1-(i - startramp)/(nsamples(x) - startramp)) :
        rampval = x.fn(1)
    writesink!(result,i,Fill(rampval,nchannels(x)))
end
@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::RampCheckpoint{S,true}) where S <: RampSignal{:on}

    ramplen = check.time
    rampval = x.fn((j-1) / ramplen)
    writesink!(result,i,Fill(rampval,nchannels(x)))
end

function Base.show(io::IO, ::MIME"text/plain",x::RampSignal{D}) where D
    if x.fn isa typeof(sinramp)
        if D == :on
            write(io,"rampon_fn(",string(x.time),")")
        elseif D == :off
            write(io,"rampoff_fn(",string(x.time),")")
        else
            error("Reached unexpected code")
        end
    else
        if D == :on
            write(io,"rampon_fn(",string(x.time),",",string(x.fn),")")
        elseif D == :off
            write(io,"rampoff_fn(",string(x.time),",",string(x.fn),")")
        else
            error("Reached unexpected code")
        end
    end
end

"""

    rampon(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the onset of a signal, smoothly transitioning from 0 to full amplitude
over the course of `len` seconds.

The function determines the shape of the ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
rampon(fun::Function) = rampon(10ms,fun)
rampon(len::Number=10ms,fun::Function=sinramp) = x -> rampon(x,len,fun)
function rampon(x,len::Number=10ms,fun::Function=sinramp)
    x = signal(x)
    x |> amplify(RampSignal(:on,x,len,fun))
end

"""

    rampoff(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the offset of a signal, smoothly transitioning from full amplitude to 0
amplitude over the course of `len` seconds.

The function determines the shape of the ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
rampoff(fun::Function) = rampoff(10ms,fun)
rampoff(len::Number=10ms,fun::Function=sinramp) = x -> rampoff(x,len,fun)
function rampoff(x,len::Number=10ms,fun::Function=sinramp)
    x = signal(x)
    x |> amplify(RampSignal(:off,x,len,fun))
end

"""

    ramp(x,[len=10ms],[fn=x -> sinpi(0.5x)])

Ramp the onset and offset of a signal, smoothly transitioning from 0 to full
amplitude over the course of `len` seconds at the start and from full to 0
amplitude over the course of `len` seconds.

The function determines the shape of the ramp and should be non-decreasing
with a range of [0,1] over the domain [0,1]. It should map over the entire
range: that is `fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
ramp(fun::Function) = ramp(10ms,fun)
ramp(len::Number=10ms,fun::Function=sinramp) = x -> ramp(x,len,fun)
function ramp(x,len::Number=10ms,fun::Function=sinramp)
    x = signal(x)
    x |> rampon(len,fun) |> rampoff(len,fun)
end

"""

    fadeto(x,y,[len=10ms],[fn=x->sinpi(0.5x)])

Append x to y, with a smooth transition lasting `len` seconds fading from
`x` to `y` (so the total length is `duration(x) + duration(y) - len`).

This fade is accomplished with a [`rampoff`](@ref) of `x` and a
[`rampon`](@ref) for `y`. `fn` should be non-decreasing with a range of [0,1]
over the domain [0,1]. It should map over the entire range: that is
`fn(0) == 0` and `fn(1) == 1`.

Both `len` and `fn` are optional arguments: either one or both can be
specified, though `len` must occur before `fn` if present.

"""
fadeto(y,fun::Function) = fadeto(y,10ms,fun)
fadeto(y,len::Number=10ms,fun::Function=sinramp) = x -> fadeto(x,y,len,fun)
function fadeto(x,y,len::Number=10ms,fun::Function=sinramp)
    x,y = uniform((x,y))
    x = signal(x)
    if ismissing(samplerate(x))
        error("Unknown sample rate is not supported by `fadeto`.")
    end
    n = insamples(Int,maybeseconds(len),samplerate(x))
    silence = signal(zero(channel_eltype(y))) |> until((nsamples(x) - n)*samples)
    x |> rampoff(len,fun) |> mix(
        y |> rampon(len,fun) |> prepend(silence))
end
