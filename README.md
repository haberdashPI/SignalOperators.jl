# SignalOperators

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://haberdashPI.github.io/SignalOperators.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://haberdashPI.github.io/SignalOperators.jl/dev)
[![Build Status](https://travis-ci.com/haberdashPI/SignalOperators.jl.svg?branch=master)](https://travis-ci.com/haberdashPI/SignalOperators.jl)
[![Codecov](https://codecov.io/gh/haberdashPI/SignalOperators.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/haberdashPI/SignalOperators.jl)

SignalOperators is a [Julia](https://julialang.org/) package that aims to provide a clean interface for generating and manipulating signals: typically sounds, but any signal regularly sampled in time can be manipulated.

```julia
using WAV
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

Read more in the [documentation](https://haberdashPI.github.io/SignalOperators.jl/stable).

## Status

The functions are relatively stable and thoroughly documented.

Everything here will run pretty fast. All calls should fall within the same order of magnitude of equivalent "raw" julia code performing the same operations.

I'm the only person I know who has made thorough use of this package: so it's obviously possible there are still some bugs or performance issues lurking about. (Please feel free to submit issues!!)

## Acknowledgements

Many thanks to @ssfrr for some great discussions during this [PR](https://github.com/JuliaAudio/SampledSignals.jl/pull/44), and related issues on the [SampledSignals](https://github.com/JuliaAudio/SampledSignals.jl) package. Those interactions definitely influenced my final design here.
