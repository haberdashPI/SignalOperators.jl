# SignalOperators

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://haberdashPI.github.io/SignalOperators.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://haberdashPI.github.io/SignalOperators.jl/dev)
[![Build Status](https://travis-ci.com/haberdashPI/SignalOperators.jl.svg?branch=master)](https://travis-ci.com/haberdashPI/SignalOperators.jl)
[![Codecov](https://codecov.io/gh/haberdashPI/SignalOperators.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/haberdashPI/SignalOperators.jl)

SignalOperators is a [Julia](https://julialang.org/) package that aims to provide a clean interface for generating and manipulating signals: typically sounds, but any signal regularly sampled in time could be manipulated.

```julia
using WAV
using SignalOperators
using SignalOperators.Units # allows the use of dB, Hz, s etc... as unitful values

# a pure tone 20 dB below a power 1 signal, with on and off ramps (for
# a smooth onset/offset)
sound1 = signal(sin,ω=1kHz) |> until(5s) |> ramp |> normpower |> amplify(-20dB)

# a sound defined by a file, matching the overall power to that of sound1
sound2 = "example.wav" |> normpower |> amplify(-20dB)

# a 1kHz sawtooth wave 
sound3 = signal(ϕ -> ϕ/π - 1,ω=1kHz) |> ramp |> normpower |> amplify(-20dB)

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

# write all of the signal to a single file, at 44.1 kHz
append(sound1,sound2,sound3,sound4,scene) |> tosamplerate(44.1kHz) |> sink("examples.wav")

```

Read more in the [documentation](https://haberdashPI.github.io/SignalOperators.jl/stable).

## Status

The functions should all *work*. However I have paid very little attention to performance, as of yet. Now that the interface and overall plan is stable, I plan to work on testing and improving any performance gaps with equivalent, bare-loop operations written in Julia.

## Acknowledgements

Many thanks to @ssfrr for some great discussions during this [PR](https://github.com/JuliaAudio/SampledSignals.jl/pull/44), and related issues on the [SampledSignals](https://github.com/JuliaAudio/SampledSignals.jl) package. Those interactions definitely influenced my final design here.
