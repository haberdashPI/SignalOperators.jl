# Manual

SignalOperators is composed of a set of functions for generating, inspecting and operating over signals. Here, a "signal" is represented as a number of frames: each frame contains some number of channels (e.g. left and right speaker) with a sampled value (e.g. `Float64`) for each channel. The values are sampled regularly in time (e.g. every 100th of a second, or 100 Hz); this is referred to as the frame rate.

## Key concepts

There are several important concepts employed across the public interface. Let's step through one of the examples from the homepage (and README.md), which demonstrates most of these concepts.

```julia
sound1 = Signal(sin,ω=1kHz) |> Until(5s) |> Ramp |> Normpower |> Amplify(-20dB)
```

This example creates a 1 kHz pure-tone (sine wave) that lasts 5 seconds. Its amplitude is 20 dB lower than a signal with unit 1 power.

There are a few things going on here: piping, the use of units, lazy evaluation, infinite length signals and unspecified frame rates.

### Piping

Almost all of the operators in SignalOperators can be piped. This means that instead of passing the first argument you can pipe it using `|>`. For example, the two statements below have the same meaning.

```julia
sound1 = Signal(sin,ω=1kHz) |> Until(5s)
sound1 = Until(Signal(sin,ω=1kHz),5s)
```

The use of piping makes it easier to read the sequence of operations that are performed on the signal.

### Units

In any place where a function needs a time or a frequency, it can be specified in appropriate units. There are many places where units can be passed. They all have a default assumed unit if a plain number without units is passed. The default units are seconds, Hertz, and radians as appropriate for the given argument.

```julia
sound1 = Signal(sin,ω=1kHz)
sound1 = Signal(sin,ω=1000)
```

Each unit is represented by a constant you can multiply by a number (in Julia, 10ms == 10*ms). To make use of the unit constants, you must call `using SignalOperators.Units`. This exports the following units: `frames`, `kframes`, `Hz`, `kHz` `s`, `ms`, `rad`, `°`, and `dB`. You can just include the ones you want using e.g. `using SignalOperators.Units: Hz`, or you can include more by adding the [`Unitful`](https://github.com/PainterQubits/Unitful.jl) package to your project and adding the desired units from there. For example, `using Unitful: MHz` would include mega-Hertz frequencies (not normally useful for sound signals). Most of the default units have been re-exported from `Unitful`. However, the `frames` unit and its derivatives (e.g. `kframes`) are unique  to the SignalOperators package. They allow you to specify the time in terms of the number of frames: e.g. at a frame rate of 100 Hz, `2s == 200frames`. Other powers of ten are represented for `frames`, (e.g. `Mframes` for mega-frames) but they are not exported (e.g. you would have to call `SignalOperators.Units: Mframes` before using `20Mframes`).

!!! note

    You can find the available powers-of-ten for units in `Unitful.prefixdict`

Note that the output of functions to inspect a signal (e.g. `duration`, `framerate`) are bare values in the default unit (e.g. seconds or Hertz). No unit is explicitly provided by the return value.

#### Decibels

You can pass an amplification value as a unitless or a unitful value in `dB`; a unitless value is not assumed to be in decibels. Instead, it's assumed to be the actual ratio by which you wish to multiply the signal. For example, `Amplify(x,2)` will make `x` twice as loud while `Amplify(x,2dB)` will increase the amplitude by two decibells.

### Lazy Evaluation

To ensure efficient signal generation, signal operators are lazy: no computations are performed until the actual signal data is requested. This lazy quality is reflected in the captilization of the operators: conceptually the operators define some new signal object which can be used to generate frames of data based on the input signal or signals. To generate these frames you call [`sink`](@ref) or [`sink!`](@ref). Generally the result of `sink` is itself a (non-lazy) signal. You can always specify the return type of `sink`, by default it tries to maintain the same representation of the signal or signals used as input, favoring the earlier arguments over later arguments.

The function [`sink`](@ref) can also write data to a file. To store the five second signal in the above example to "example.wav" we could write the following.

```julia
sound1 |> sink("example.wav")
```

In this case `sound1` had no defined frame rate, so the default frame rate
of 44.1khz will be used. The absence of an explicit frame rate will raise a
warning.

#### Non-lazy operators

If you prefer the result of an operator to be non-lazy, so you don't have to call `sink` first, you can make use the lower case versions of the operators. These operators do not allow for piping, as this would typically be quite
inefficient. If you want to combine multiple operators, they should normally be evaluated lazily.

### Infinite lengths

Some of the ways you can define a signal lead to an infinite length signal.
To allow for calls to `sink`, you have to specify the length, using
[`Until`](@ref). For example, when using `Signal(sin)`, the signal is an
infinite length sine wave. That's why, in the example above, we use
[`Until`](@ref) to specify the length, as follows.

```julia
Signal(sin,ω=1kHz) |> Until(5s)
```

Infinite lengths are represented as the value [`inflen`](@ref) (e.g. when calling [`nframes`](@ref)). This has overloaded definitions of various operators to play nicely with ordering, arithmetic etc...

### Unspecified frame rates

You may notice that the above signal has no defined frame rate. Such a signal is defined by a function, and can be sampled at whatever rate you desire. If you add a signal to the chain of operations that does have a defined frame rate, the unspecified frame rate will be resolved to that same rate (see signal promotion, below).

### Signal promotion

A final concept, which is not as obvious from the examples, is the use of
automatic signal promotion. When multiple signals are passed to the same
operator, and they have a different number of channels or different frame
rate, the signals are first converted to the highest fidelity format and then
operated on. This allows for a relatively seamless chain of operations where
you don't have to worry about the specific format of the signal, and you
won't loose information about your signals unless you explicitly request a
lower fidelity signal format (e.g. using [`ToChannels`](@ref) or
[`ToFramerate`](@ref)).

## Signal generation

There are four basic types that can be interpreted as signals: numbers,
arrays, functions and files. Internally the function [`Signal`](@ref) is
called on any object passed to a function that operates on a
signal; you can call [`Signal`](@ref) yourself if you want to specify more
information. For example, you may want to provide the exact frame rate the
signal should be interpreted to have.

### Numbers

A number is treated as an infinite length signal, with unknown frame rate.

```julia
1 |> Until(1s) |> toframerate(10Hz) |> sink == ones(10)
```

### Arrays

A standard array is treated as a finite signal with unknown frame rate.

```julia
rand(10,2) |> toframerate(10Hz) |> sink |> duration == 1
```

An `AxisArray`, `DimesnionalArray` or `SampleBuf` (form [`SampledSignals`](https://github.com/JuliaAudio/SampledSignals.jl)) is treated as a finite signal with a known frame rate (and is the default output of [`sink`](@ref))

```julia
using AxisArrays
x = AxisArray(rand(10,1),Axis{:time}(range(0,1,length=10)))
framerate(x) == 10
```

### Functions

A single argument function of time (in seconds) can be treated as an infinite
signal. It can be also be a function of radians if you specify a frequency
using `ω` (or `frequency`). See [`Signal`](@ref)'s documentation for more
details.

```julia
Signal(sin,ω=1kHz) |> duration |> isinf == true
```

A small exception to this is `randn`. It can be used directly as a signal with unknown frame rate.

```julia
randn |> duration == isinf
```

### Files

A file is interpreted as an audio file to be loaded into memory. You must
include the `WAV` or `LibSndFile` package for this to work.

```julia
using WAV
x = Signal("example.wav")
```

## Signal inspection

You can examine the properties of a signal using [`nframes`](@ref), [`nchannels`](@ref), [`framerate`](@ref), and [`duration`](@ref).

## Signal operators

There are several categories of signal operators: extending, cutting, filtering, ramping, and mapping.

### Extending

You can extend a signal using [`Pad`](@ref) or [`Append`](@ref). A padded signal becomes infinite by appending the signal by a repeated value, usually `one` or `zero`. You can append two or more signals (or [`Prepend`](@ref)) so they occur one after another.

```julia
Pad(x,zero) |> duration |> isinf == true
Append(x,y,z) |> duration == duration(x) + duration(y) + duration(z)
```

!!! note

    You cannot append more than one new signal within a pipe. That is,
    the following will throw an error.

    ```julia
    # Don't do this!
    x |> Append(y,z)
    ```

    This is because `Append(y,z)` does not return a function to be piped (as
    `Append(y)` does). It returns a signal with `y` followed by `z`. You can instead call this as follows.

    ```julia
    # This will do what you want!
    x |> Append(y) |> Append(z)
    ```


### Cutting

You can cut signals apart, removing either the end of the signal ([`Until`](@ref)) or the beginning ([`After`](@ref)). The operations are exact compliments of one another.

```julia
Append(Until(x,2s),After(x,2s)) |> nframes == nframes(x)
```

### Filtering

You can filter signals, removing undesired frequencies using [`Filt`](@ref).

```julia
Signal(randn) |> Filt(Lowpass,20Hz)
```

!!! warning

    If you write `using DSP` you will have to also write `dB = SignalOperators.Units.dB` if you want to make use of the proper meaning of `dB` for `SignalOperators`: `DSP` also defines `dB`.

An unusual filter is [`Normpower`](@ref): it computes the root mean squared power of the signal and then normalizes each frame by that value.

### Ramping

A Ramp allows for smooth transitions between 0 amplitude and the full amplitude of the signal. It is useful to avoid clicks in the onset or offset of a sound. For example, pure-tones are typically ramped when presented.

```julia
Signal(sin,ω=2kHz) |> Until(5s) |> Ramp
```

You can ramp only the start of a signal ([`RampOn`](@ref)), or the end of it ([`RampOff`](@ref)) and you can use ramps to create a smooth transition between two signals ([`FadeTo`](@ref)).

### Mapping

Probably the most powerful operator is [`MapSignal`](@ref). It works a lot like `map` but automatically promotes the signals, as with all operators, *and* it pads the end of the signal appropriately, so different length signals can be combined. The output is always the length of the longest *finite*-length signal.

```julia
a = Signal(sin,ω=2kHz) |> Until(2s)
b = Signal(sin,ω=1kHz) |> Until(3s)
a_minus_b = MapSignal(-,a,b)
```

The function [`MapSignal`](@ref) cannot itself be piped, due to ambiguity in the arguments, but shortcuts for this function have been provided for addition ([`Mix`](@ref)) and multiplication ([`Amplify`](@ref)), the two most common operations, and these two shortcuts have piped versions available.

```julia
a_plus_b = a |> Mix(b)
a_times_b = a |> Amplify(b)
```

You can also add or select out channels using [`AddChannel`](@ref) and [`SelectChannel`](@ref), which are defined in terms of calls to [`MapSignal`](@ref). These use a variant of [`MapSignal`](@ref) where the keyword `bychannel` is set to `false` (see `MapSignal`'s documentation for details).
