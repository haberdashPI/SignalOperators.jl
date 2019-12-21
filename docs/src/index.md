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
sound1 = signal(sin,ω=1kHz) |> until(5s) |> ramp |> normpower |> amplify(-20dB)

# a sound defined by a file, matching the overall power to that of sound1
sound2 = "example.wav" |> normpower |> amplify(-20dB)

# a 1kHz sawtooth wave
sound3 = signal(ϕ -> ϕ-π,ω=1kHz) |> ramp |> normpower |> amplify(-20dB)

# a 5 Hz amplitude modulated noise
sound4 = randn |>
    amplify(signal(ϕ -> 0.5sin(ϕ) + 0.5,ω=5Hz)) |>
    until(5s) |> normpower |> amplify(-20dB)

# a 1kHz tone surrounded by a notch noise
SNR = 5dB
x = signal(sin,ω=1kHz) |> until(1s) |> ramp |> normpower |> amplify(-20dB + SNR)
y = signal(randn) |> until(1s) |> bandstop(0.5kHz,2kHz) |> normpower |>
  amplify(-20dB)
scene = mix(x,y)

# write all of the signals to a single file, at 44.1 kHz
append(sound1,sound2,sound3,sound4,scene) |> toframerate(44.1kHz) |> sink("examples.wav")

```

## Acknowledgements

Many thanks to @ssfrr for some great discussions during this [PR](https://github.com/JuliaAudio/SampledSignals.jl/pull/44), and related issues on the [SampledSignals](https://github.com/JuliaAudio/SampledSignals.jl) package. Those interactions definitely influenced my final design here.
