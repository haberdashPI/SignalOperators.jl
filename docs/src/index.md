# SignalOperators.jl

SignalOperators is a [Julia](https://julialang.org/) package that aims to provide a clean interface for generating and manipulating signals: typically sounds, but any signal regularly sampled in time can be manipulated.

You can install it in Julia by starting the Pkg prompt (hit `]`), and using the `add` command.

```julia
(1.2) pkg> add SignalOperators
```

As a preview of functionality, here are some example sound generation routines. You can find more detailed information in the manual and reference.

```julia
using SignalOperators
using SignalOperators.Units # allows the use of dB, Hz, s etc... as unitful values

# a pure tone 20 dB below a power 1 signal, with on and off ramps (for
# a smooth onset/offset)
sound1 = Signal(sin,ω=1kHz) |> Until(5s) |> Ramp |> Normpower |> Amplify(-20dB)

# a sound defined by a file, matching the overall power to that of sound1
sound2 = "example.wav" |> Normpower |> Amplify(-20dB)

# a 1kHz sawtooth wave
sound3 = Signal(ϕ -> ϕ-π,ω=1kHz) |> Ramp |> Normpower |> Amplify(-20dB)

# a 5 Hz amplitude modulated noise
sound4 = randn |>
    Amplify(Signal(ϕ -> 0.5sin(ϕ) + 0.5,ω=5Hz)) |>
    Until(5s) |> Normpower |> Amplify(-20dB)

# a 1kHz tone surrounded by a notch noise
SNR = 5dB
x = Signal(sin,ω=1kHz) |> Until(1s) |> Ramp |> Normpower |> Amplify(-20dB + SNR)
y = Signal(randn) |> Until(1s) |> bandstop(0.5kHz,2kHz) |> Normpower |>
  Amplify(-20dB)
scene = Mix(x,y)

# write all of the signals to a single file, at 44.1 kHz
Append(sound1,sound2,sound3,sound4,scene) |> ToFramerate(44.1kHz) |> sink("examples.wav")

```

## Acknowledgements

Many thanks to @ssfrr for some great discussions during this [PR](https://github.com/JuliaAudio/SampledSignals.jl/pull/44), and related issues on the [SampledSignals](https://github.com/JuliaAudio/SampledSignals.jl) package. Those interactions definitely influenced my final design here.
