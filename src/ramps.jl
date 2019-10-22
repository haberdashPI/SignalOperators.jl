
export rampon, rampoff, ramp, fadeto, sinramp

sinramp(x) = sinpi(0.5x)

function rampon_fn(x,len,fun)
    time = inseconds(Float64,len,samplerate(x))
    RampOnFn{float(channel_eltype(x)),typeof(fun)}(fun,time)
end
struct RampOnFn{El,Fn} <: Functor
    ramp::Fn
    time::Float64
end
(fn::RampOnFn{El})(t) where El =
    t ≤ fn.time ? El(fn.ramp(t/fn.time)) : one(El)
Base.string(x::RampOnFn{<:Any,<:typeof(sinramp)}) =
    string("rampon_fn(",x.time,")")
Base.string(x::RampOnFn) = string("rampon_fn(",x.time,",",x.ramp,")")

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
    signal(rampon_fn(x,len,fun),samplerate(x)) |> amplify(x)
end

function rampoff_fn(x,len,fun)
    time = inseconds(Float64,len,samplerate(x))
    ramp_start = duration(x) - time
    if ismissing(ramp_start)
        error("Uknown signal duration: cannot determine rampoff parameters. ",
              "Define the samplerate or signal length earlier in the ",
              "processing chain.")
    end
    RampOffFn{float(channel_eltype(x)),typeof(fun)}(fun,ramp_start,time)
end
struct RampOffFn{El,Fn} <: Functor
    ramp::Fn
    ramp_start::Float64
    time::Float64
end
(fn::RampOffFn{El})(t) where El =
    t < fn.ramp_start ? one(El) : El(fn.ramp(1.0 - (t-fn.ramp_start)/fn.time))
Base.string(x::RampOffFn{<:Any,<:typeof(sinramp)}) = string("rampoff_fn(",x.time,")")
Base.string(x::RampOffFn) = string("rampoff_fn(",x.time,",",x.ramp,")")

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
    signal(rampoff_fn(x,len,fun),samplerate(x)) |> amplify(x)
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
    n = insamples(Int,maybeseconds(len),samplerate(x))
    silence = signal(zero(channel_eltype(y))) |> until((nsamples(x) - n)*samples)
    x |> rampoff(len,fun) |> mix(
        y |> rampon(len,fun) |> prepend(silence))
end
