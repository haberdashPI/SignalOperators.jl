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
## Signal Operators

### Basic Operators

```@docs
Until
until
After
after
Append
append
Prepend
preprend
Pad
mirror
cycle
lastframe
SignalOperators.valuefunction
```

### Mapping Operators

```@docs
Filt
Normpower
MapSignal
mapsignal
Mix
mix
Amplify
amplify
AddChannel
addchannel
SelectChannel
selectchannel
```

### Ramping Operators

```@docs
RampOn
rampon
RampOff
rampoff
Ramp
ramp
FadeTo
fadeto
```

### Reformatting Operators

```@docs
ToFramerate
toframerate
ToChannels
tochannels
ToEltype
toeltype
Format
format
Uniform
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