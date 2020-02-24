using DSP: FIRFilter, resample_filter
export ToFramerate, ToChannels, Format, Uniform, ToEltype,
    toframerate, tochannels, format, toeltype

"""

    ToFramerate(x,fs;blocksize)

Change the frame rate of `x` to the given frame rate `fs`. The underlying
implementation depends on whether the input is a computed or data signal,
as determined by [`EvalTrait`](@ref).

Computed signals (e.g. `Signal(sin)`) are resampled exactly: the result is
simply computed for more time points or fewer time points, so as to generate
the appropriate number of frames.

Data-based signals (`Signal(rand(50,2))`) are resampled using filtering (akin
to `DSP.resample`). In this case you can use the keyword arugment `blocksize`
to change the analysis window used. See [`Filt`](@ref) for more
details. Setting `blocksize` for a computed signal will succeed,
but different `blocksize` values have no effect on the underlying
implementation.

# Implementation

You need only implement this function for [custom signals](@ref
custom_signals) for particular scenarios, described below.

## Custom Computed Signals

If you implement a new sigal type that is a computed signal, you must
implement `ToFramerate` with the following type signature.

```julia

function ToFramerate(x::MyCustomSignal,s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,framerate;blocksize)

    ## ...
end
```

The result should be a new version of the computed signal with the given
frame rate.

## Handling missing frame rates

If you implement a new signal type that can handle missing frame rate values,
you will need to implement the following version of `ToFramerate` so that
a known frame rate can be applied to a signal with a missing frame rate.

```julia

function ToFramerate(x::MyCustomSignal,s::IsSignal{<:Any,Missing},
    evaltrait,framerate;blocksize)

    ## ...
end
```

The result should be a new version of the signal with the specified frame rate.

"""
ToFramerate(fs;blocksize=default_blocksize) =
    x -> ToFramerate(x,fs;blocksize=blocksize)
ToFramerate(x,fs;blocksize=default_blocksize) =
    ismissing(fs) && ismissing(framerate(x)) ? x :
        coalesce(inHz(fs) == framerate(x),false) ? x :
        ToFramerate(x,SignalTrait(x),EvalTrait(x),inHz(fs);blocksize=blocksize)
ToFramerate(x,::Nothing,ev,fs;kwds...) = nosignal(x)

"""
    toframerate(x,fs;blocksize)

Equivalent to `sink(ToFramerate(x,fs;blocksize=blocksize))`

## See also

[`ToFramerate`](@ref)

"""
toframerate(x,fs;blocksize=default_blocksize) =
    sink(ToFramerate(x,fs;blocksize=blocksize))

ToFramerate(x,::IsSignal,::DataSignal,::Missing;kwds...) = x
ToFramerate(x,::IsSignal,::ComputedSignal,::Missing;kwds...) = x

function ToFramerate(x,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize)
    __ToFramerate__(x,s,fs,blocksize)
end

function (fn::ResamplerFn)(fs)
    h = resample_filter(fn.ratio)
    self = FIRFilter(h, fn.ratio)
    τ = timedelay(self)
    setphase!(self, τ)

    self
end
filterstring(fn::ResamplerFn) =
    string("ToFramerate(",inHz(fn.fs)*Hz,")")

function maybe_rationalize(r)
    x = rationalize(r)
    # only use rational number if it is a small integer ratio
    if max(numerator(x),denominator(x)) ≤ 3
        x
    else
        r
    end
end

function __ToFramerate__(x,s::IsSignal{T},fs,blocksize) where T
    # copied and modified from DSP's `resample`
    ratio = maybe_rationalize(fs/framerate(x))
    init_fs = framerate(x)
    if ratio == 1
        x
    else
        Filt(x,s,ResamplerFn(ratio,fs);blocksize=blocksize,newfs=fs)
    end
end

"""

    ToChannels(x,ch)

Force a signal to have `ch` number of channels, by mixing channels together
or broadcasting a single channel over multiple channels.

"""
ToChannels(ch) = x -> ToChannels(x,ch)
ToChannels(x,ch) = ToChannels(x,SignalTrait(x),ch)
ToChannels(x,::Nothing,ch) = ToChannels(Signal(x),ch)

"""
    tochannels(x,ch)

Equivalent to `sink(ToChannels(x,ch))`

## See also

[`ToFramerate`](@ref)

"""
tochannels(x,ch) = sink(ToChannels(x,ch))

struct AsNChannels
    ch::Int
end
(fn::AsNChannels)(x) = tuple((x[1] for _ in 1:fn.ch)...)
mapstring(fn::AsNChannels) = string("ToChannels(",fn.ch)

struct As1Channel
end
(fn::As1Channel)(x) = sum(x)
mapstring(fn::As1Channel) = string("ToChannels(1")

function ToChannels(x,::IsSignal,ch)
    if ch == nchannels(x)
        x
    elseif ch == 1
        OperateOn(As1Channel(),x,bychannel=false)
    elseif nchannels(x) == 1
        OperateOn(AsNChannels(ch),x,bychannel=false)
    else
        error("No rule to convert signal with $(nchannels(x)) channels to",
            " a signal with $ch channels.")
    end
end


struct ToEltypeFn{El}
end
(fn::ToEltypeFn{El})(x) where El = convert(El,x)
mapstring(fn::ToEltypeFn{El}) where El = string("ToEltype(",El,")")

"""
    ToEltype(x,T)

Converts individual samples in signal `x` to type `T`.
"""
ToEltype(::Type{T}) where T = x -> ToEltype(x,T)
ToEltype(x,::Type{T}) where T = OperateOn(ToEltypeFn{T}(),x)

"""
    toeltype(x,T)

Equivalent to `sink(ToEltype(x,T))`

## See also

[`ToEltype`](@ref)

"""
toeltype(x,::Type{T}) where T = sink(ToEltype(x,T))

"""

    Format(x,fs,ch)

Efficiently convert both the framerate (`fs`) and channels `ch` of signal
`x`. This selects an optimal ordering for `ToFramerate` and `ToChannels` to
avoid redundant computations.

"""
function Format(x,fs,ch=nchannels(x))
    if ch > 1 && nchannels(x) == 1
        ToFramerate(x,fs) |> ToChannels(ch)
    else
        ToChannels(x,ch) |> ToFramerate(fs)
    end
end

"""
    format(x,fs,ch)

Equivalent to `sink(Format(x,fs,ch))`

## See also

[`Format`](@ref)

"""
format(x,fs,ch) = sink(Format(x,fs,ch))

"""

    Uniform(xs;channels=false)

Promote the frame rate (and optionally the number of channels) to be the
highest frame rate (and optionally highest channel count) of the iterable of signals `xs`.

!!! note

    `Uniform` rarely needs to be called directly. It is called implicitly on
    all passed signals, within the body of operators such as
    [`OperateOn`](@ref).

"""
function Uniform(xs;channels=false)
    xs = Signal.(xs)
    if any(!ismissing,SignalOperators.framerate.(xs))
        framerate = maximum(skipmissing(SignalOperators.framerate.(xs)))
    else
        framerate = missing
    end
    if !channels
        Format.(xs,framerate)
    else
        ch = maximum(skipmissing(nchannels.(xs)))
        Format.(xs,framerate,ch)
    end
end
