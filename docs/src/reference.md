# Reference

## Signal Generation

```@docs
Signal
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
sampletype
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
prepend
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
normpower
OperateOn
Operate
operate
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
