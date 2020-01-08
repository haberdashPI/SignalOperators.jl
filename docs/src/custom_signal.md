# [Custom Signals](@id custom_signals)

To treat new custom objects as signals, you must support the signal
interface. Such an object must return an appropriate
[`SignalOperators.IsSignal`](@ref) object when calling
[`SignalOperators.SignalTrait`](@ref).

Any object returning [`SignalOperators.IsSignal`](@ref) should implement
[`SignalOperators.nextblock`](@ref), which is used to sequentially retrieve
blocks from a signal. If your custom signal is an `AbstractArray` there is a
fallback implementaiton of [`SignalOperators.nextblock`](@ref) which only
requires you to implement [`SignalOperators.timeslice`](@ref)

Analogous to `Base.iterate`, [`SignalOperators.nextblock`](@ref) will return
`nothing` when there are no more blocks to produce. The blocks returned by
[`SignalOperators.nextblock`](@ref) must implement the following two methods.

* [`nframes`](@ref) Like a signal, each block has a fixed number of frames. Unlike signals, this cannot be an infinite or missing value. The implementation should be a fast, type-stable function.
* [`SignalOperators.frame`](@ref) Individual frames of the block can be accessed by their index within the block (falling in the range of `1:nframes(block)`). This should be a fast, type-stable function. The method is guaranteed to only be called at most once for each index in the block. Normally, you should annotate it with `@Base.propagate_inbounds` just as you would an implementation of `Baes.getindex`.

If you intend to return blocks that are arrays of data you can use [`SignalOperators.ArrayBlock`](@ref), which will implement `nframes` and `frame` for you.

The custom signal will also need to implement methods from SignalBase for signal inspection.

* [`channeltype`](@ref) - to indicate the number of channels of the signal
* [`nchannels`](@ref) - to indicate how many channels per frame there are in this signal
* [`nframes`](@ref) - to indicate how many frames are present in the signal; this may be an infinite or missing value
* [`framerate`](@ref) - to indicate the frame rate of the signal

Finally, there are several **optional** methods you can define for signals as
well.

* [`Signal`](@ref) - to enable one more other types to be interpreted as your custom signal type
* [`duration`](@ref) - to allow `missing` values for `nframes` and non-missing values for `duration`
* [`SignalOperators.EvalTrait`](@ref) and [`ToFramerate`](@ref) - to enable custom handling of signal resmapling