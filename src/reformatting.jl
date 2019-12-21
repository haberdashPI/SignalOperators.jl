using DSP: FIRFilter, resample_filter
export toframerate, tochannels, format, uniform, toeltype

"""

    toframerate(x,fs;blocksize)

Change the frame rate of `x` to the given frame rate `fs`. The underlying
implementation depends on whether the input is a computed or data signal,
as determined by [`EvalTrait`](@ref).

Computed signals (e.g. `signal(sin)`) are resampled exactly: the result is
simply computed for more time points or fewer time points, so as to generate
the appropriate number of frames.

Data-based signals (`signal(rand(50,2))`) are resampled using filtering (akin
to `DSP.resample`). In this case you can use the keyword arugment `blocksize`
to change the analysis window used. See [`filtersignal`](@ref) for more
details. Setting `blocksize` for a computed signal will succeed,
but different `blocksize` values have no effect on the underlying
implementation.

# Implementation

You need only implement this function for custom signals for particular
scenarios, described below.

## Custom Computed Signals

If you implement a new sigal type that is a computed signal, you must
implement `toframerate` with the following type signature.

```julia

function toframerate(x::MyCustomSignal,s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,framerate;blocksize)

    ## ...
end
```

The result should be a new version of the computed signal with the given
frame rate.

## Handling missing frame rates

If you implement a new signal type that can handle missing frame rate values,
you will need to implement the following version of `toframerate` so that
a known frame rate can be applied to a signal with a missing frame rate.

```julia

function toframerate(x::MyCustomSignal,s::IsSignal{<:Any,Missing},
    evaltrait,framerate;blocksize)

    ## ...
end
```

The result should be a new version of the signal with the specified frame rate.

"""
toframerate(fs;blocksize=default_blocksize) =
    x -> toframerate(x,fs;blocksize=blocksize)
toframerate(x,fs;blocksize=default_blocksize) =
    ismissing(fs) && ismissing(framerate(x)) ? x :
        coalesce(inHz(fs) == framerate(x),false) ? x :
        toframerate(x,SignalTrait(x),EvalTrait(x),inHz(fs);blocksize=blocksize)
toframerate(x,::Nothing,ev,fs;kwds...) = nosignal(x)

toframerate(x,::IsSignal,::DataSignal,::Missing;kwds...) = x
toframerate(x,::IsSignal,::ComputedSignal,::Missing;kwds...) = x

function toframerate(x,s::IsSignal{<:Any,<:Number},::DataSignal,fs::Number;blocksize)
    __toframerate__(x,s,fs,blocksize)
end

function (fn::ResamplerFn)(fs)
    h = resample_filter(fn.ratio)
    self = FIRFilter(h, fn.ratio)
    τ = timedelay(self)
    setphase!(self, τ)

    self
end
filterstring(fn::ResamplerFn) =
    string("toframerate(",inHz(fn.fs)*Hz,")")

function maybe_rationalize(r)
    x = rationalize(r)
    # only use rational number if it is a small integer ratio
    if max(numerator(x),denominator(x)) ≤ 16
        x
    else
        r
    end
end

function __toframerate__(x,s::IsSignal{T},fs,blocksize) where T
    # copied and modified from DSP's `resample`
    ratio = maybe_rationalize(fs/framerate(x))
    init_fs = framerate(x)
    if ratio == 1
        x
    else
        filtersignal(x,s,ResamplerFn(ratio,fs);blocksize=blocksize,newfs=fs)
    end
end

"""

    tochannels(x,ch)

Force a signal to have `ch` number of channels, by mixing channels together
or broadcasting a single channel over multiple channels.

"""
tochannels(ch) = x -> tochannels(x,ch)
tochannels(x,ch) = tochannels(x,SignalTrait(x),ch)
tochannels(x,::Nothing,ch) = tochannels(signal(x),ch)

struct AsNChannels
    ch::Int
end
(fn::AsNChannels)(x) = tuple((x[1] for _ in 1:fn.ch)...)
mapstring(fn::AsNChannels) = string("tochannels(",fn.ch)

struct As1Channel
end
(fn::As1Channel)(x) = sum(x)
mapstring(fn::As1Channel) = string("tochannels(1")

function tochannels(x,::IsSignal,ch)
    if ch == nchannels(x)
        x
    elseif ch == 1
        mapsignal(As1Channel(),x,bychannel=false)
    elseif nchannels(x) == 1
        mapsignal(AsNChannels(ch),x,bychannel=false)
    else
        error("No rule to convert signal with $(nchannels(x)) channels to",
            " a signal with $ch channels.")
    end
end


struct ToEltypeFn{El}
end
(fn::ToEltypeFn{El})(x) where El = convert(El,x)
mapstring(fn::ToEltypeFn{El}) where El = string("toeltype(",El,")")

"""
    toeltype(x,T)

Converts individual frames in signal `x` to type `T`.
"""
toeltype(::Type{T}) where T = x -> toeltype(x,T)
toeltype(x,::Type{T}) where T = mapsignal(ToEltypeFn{T}(),x)

"""

    format(x,fs,ch)

Efficiently convert both the framerate (`fs`) and channels `ch` of signal
`x`. This selects an optimal ordering for `toframerate` and `tochannels` to
avoid redundant computations.

"""
function format(x,fs,ch=nchannels(x))
    if ch > 1 && nchannels(x) == 1
        toframerate(x,fs) |> tochannels(ch)
    else
        tochannels(x,ch) |> toframerate(fs)
    end
end

"""

    uniform(xs;channels=false)

Promote the frame rate (and optionally the number of channels) to be the
highest frame rate (and optionally highest channel count) of the iterable of signals `xs`.

!!! note

    `uniform` rarely needs to be called directly. It is called implicitly on
    all passed signals, within the body of operators such as
    [`mapsignal`](@ref).

"""
function uniform(xs;channels=false)
    xs = signal.(xs)
    if any(!ismissing,SignalOperators.framerate.(xs))
        framerate = maximum(skipmissing(SignalOperators.framerate.(xs)))
    else
        framerate = missing
    end
    if !channels
        format.(xs,framerate)
    else
        ch = maximum(skipmissing(nchannels.(xs)))
        format.(xs,framerate,ch)
    end
end
