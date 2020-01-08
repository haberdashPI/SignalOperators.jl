# [Custom Signals](@id custom_signals)

To treat new custom objects as signals, you must support the signal
interface. Such an object must return an appropriate
[`SignalOperators.IsSignal`](@ref) object when calling
[`SignalOperators.SignalTrait`](@ref).

`IsSignal` is an emptry struct that has three type parameters, indicating the
[`sampletype`](@ref) the type of [`framerate`](@ref) and the type used to
represent the length returned by [`nframes`](@ref). For example, for an array
`SignalTrait` is implemented as follows.

```julia
SignalTrait(x::Type{<:Array{T}}) where T = IsSignal{T,Missing,Int}
```

All signals should implement the appropriate methods from [`SignalBase`](https://github.com/haberdashPI/SignalBase.jl).
What additional methods you should implement depends on what kind of signal
you have.

## AbstractArray objects

If your signal is an array of some kind you should implement
[`SignalOperators.timeslice`](@ref), which should return a requested range of
frames from the signal.

You should also consider defining your array type to be a [custom sink](@ref custom_sinks).

## Other objects

Any other type of signal should implement
[`SignalOperators.nextblock`](@ref), which is used to sequentially retrieve
blocks from a signal.

Analogous to `Base.iterate`, [`SignalOperators.nextblock`](@ref) will return
`nothing` when there are no more blocks to produce.

If the returned blocks will be represetend by an array of numbers, then
[`SignalOperators.ArrayBlock`](@ref) should be used.

In other cases, such as when you want to compute individual frames of the block on-the-fly, you should return an object that implements the following two methods.

* [`nframes`](@ref) Like a signal, each block has some number of frames. Unlike signals, this cannot be an infinite or missing value. The implementation should be a fast, type-stable function.
* [`SignalOperators.frame`](@ref) Individual frames of the block can be accessed by their index within the block (falling in the range of `1:nframes(block)`). This should be a fast, type-stable function. The method is guaranteed to only be called at most once for each index in the block.

## Optional Methods

There are several **optional** methods you can define for signals as
well.

* [`Signal`](@ref) - to enable one more other types to be interpreted as your custom signal type
* [`SignalOperators.EvalTrait`](@ref) and [`ToFramerate`](@ref) - to enable custom handling of signal resmapling