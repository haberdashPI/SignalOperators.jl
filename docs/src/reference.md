# Reference

## Signal Generation

```@docs
signal
sink
sink!
```

## Signal Inspection
```@docs
inflen
duration
nframes
nchannels
framerate
channel_eltype
```

## Signal Reformatting

```@docs
toframerate
tochannels
toeltype
format
uniform
```

## Signal Operators
```@docs
until
after
append
prepend
pad
mirror
cycle
lastframe
SignalOperators.valuefunction
filtersignal
lowpass
highpass
bandpass
bandstop
normpower
mapsignal
mix
amplify
addchannel
channel
rampon
rampoff
ramp
fadeto
```

## Custom Signals
```@docs
SignalOperators.SignalTrait
SignalOperators.IsSignal
SignalOperators.EvalTrait
SignalOperators.nextblock
SignalOperators.frame
SignalOperators.timeslice
SignalOperators.ArrayBlock
```

## Custom Sinks
```@docs
SignalOperators.initsink
SignalOperators.sink_helper!
```

```