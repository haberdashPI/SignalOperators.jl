# [Custom Signals](@id custom_signals)

Many signals can be readily created by passing a function to [`signal`](@ref)
or by using [`mapsignal`](@ref). However, in some cases it may be preferable
to define a new signal type entirely. This allows for the most flexibility in
terms of how the signal will behave within a chain of signal operators.

To be propperly treated as a signal, an object must return an appropriate
[`SignalOperators.IsSignal`](@ref) object when calling [`SignalOperators.SignalTrait`](@ref).

Any object returning [`SignalOperators.IsSignal`](@ref) should implement
[`SignalOperators.nextblock`](@ref), which is used to sequentially retrieve
blocks from a signal. If your custom signal is an `AbstractArray` there is a
fallback implementaiton of [`SignalOperators.nextblock`](@ref) which only
requires you to implement [`SignalOperators.timeslice`](@ref)

Analogous to `Base.iterate`, [`SignalOperators.nextblock`](@ref) will return
`nothing` when there are no more blocks to produce. The blocks returned by
[`SignalOperators.nextblock`](@ref) must implement the following two methods.

* [`nsamples`](@ref) Like a signal, each block has a fixed number of samples. Unlike signals, this cannot be an infinite or missing value. It should be a fast, type-stable function.
* [`SignalOperators.sample`](@ref) Individual samples of the block can be accessed by their index within the block (falling in the range of `1:nsamples(block)`). This should be a fast, type-stable function. The method is guaranteed to only be called at most once for each index in the block. Normally, you should annotate it with `@Base.propagate_inbounds` just as you would an implementation of `Baes.getindex`.

If you intend to simply returns blocks using arrays of data you can use [`SignalOperators.ArrayBlock`](@ref), which will implement `nsamples` and `sample` for you.

The custom signal will also need to implement methods for the following, signal-inspection methods.

* [`nsamples`](@ref) - to indicate how many samples are present in the signal;
this may be an infinite or missing value.
* [`samplerate`](@ref) - to indicate the sampling rate of the signal
* [`nchannels`](@ref) - to indicate how many channels per sample there are in this signal

Finally, there are several **optional** methods you can define for signals as
well.

* [`signal`](@ref) - to enable one more other types to be interpreted as your
custom signal type.
* [`duration`](@ref) - to allow `missing` values for `nsamples` and non-missing values for `duration`.
* [`SignalOperators.EvalTrait`](@ref) and [`tosamplerate`](@ref) - to enable custom handling of
signal resmapling.