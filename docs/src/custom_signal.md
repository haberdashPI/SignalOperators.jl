# [Custom Signals](@id custom_signals)

To treat new custom objects as signals, you must support the signal
interface. Such an object must return an appropriate
[`SignalOperators.IsSignal`](@ref) object when calling
[`SignalOperators.SignalTrait`](@ref).

`IsSignal` is an empty struct that has three type parameters, indicating the
[`sampletype`](@ref) the type of [`framerate`](@ref) and the type used to
represent the length returned by [`nframes`](@ref). For example, for an array
`SignalTrait` is implemented as follows.

```julia
SignalTrait(x::Type{<:Array{T}}) where T = IsSignal{T,Missing,Int}
```

All signals should implement the appropriate methods from
[`SignalBase`](https://github.com/haberdashPI/SignalBase.jl).

The signal should implement [`SignalOperators.iterateblock`](@ref), which is used to
sequentially retrieve blocks of data from a signal, analogous to `Base.iterate`.

Note that a method is already defined for `AbstractArray` objects, assuming the last
dimension is time. If you have an `AbstractArray` conforming to this assumption you don't
need to implement this method. (`AbstractArray` objects should also consider registering as
a [custom sink](@ref custom_sinks)).

## Optional Methods

There are several **optional** methods you can define for signals as
well.

* [`Signal`](@ref) -- to enable one or more other types to be interpreted as your custom signal type
* [`SignalOperators.EvalTrait`](@ref) and [`ToFramerate`](@ref) -- to enable custom handling of signal resampling; useful when your data is computed on the fly.