# [Custom Sinks] (@id custom_sinks)

You can create custom sinks, which can be passed to [`sink`](@ref) or [`sink!`](@ref) by defining two methods: [`SignalOperators.initsink`](@ref) and [`SignalOperators.sink_helper!`](@ref). The first method is called when
a call to `sink` is made (e.g. `sink(MyCustomSink)`). The second method
is called inside `sink!` and provides the core operation to write blocks of samples to the sink.

Implementing `initsink` is not strictly necessary. If you do not implement
`initsink` you will only be able to write to the sink using `sink!`.