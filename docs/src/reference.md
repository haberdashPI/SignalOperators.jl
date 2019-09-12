
# Signal Generation

```@docs
signal
zero(::SignalOperators.AbstractSignal)
one(::SignalOperators.AbstractSignal)
sink
sink!
```

## Signal Inspection
```@docs
duration
nsamples
nchannels
samplerate
```

## Signal Manipulation
```@docs
until
after
append
prepend
pad
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

## Reformatting

```@docs
tosamplerate
tochannels
format
uniform
```