# [Custom Sinks] (@id custom_sinks)

You can create custom sinks, which can be passed to [`sink`](@ref) or
[`sink!`](@ref) by defining two methods: [`SignalOperators.initsink`](@ref)
and [`SignalOperators.sink_helper!`](@ref). The first method is called when a
call to `sink` is made (e.g. `sink(MyCustomSink)`). The second method is
called inside `sink!` and provides the core operation to write blocks of
frames to the sink. There is already a method of `sink_helper!` defined for
`AbstractArray` objects, so you likely do not need to implement it if your
custom sink is an `AbtractArray`.

You may also want to implement a constructor of the sink type that takes a
single argument `x` of type `SignalOperators.AbstractSignal`. This should
generally just call `sink(x,CustomSink)`.

!!! note

    Implementing `initsink` is not strictly necessary. If you do not implement
    `initsink` you will only be able to write to the sink using `sink!`.