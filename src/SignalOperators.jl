module SignalOperators
using Requires, DSP, LambdaFn, Unitful, Compat, PrettyPrinting, FillArrays,
    FileIO

using PrettyPrinting: best_fit, indent, list_layout, literal, pair_layout
using SignalBase
import SignalBase: nframes, nchannels, sampletype, framerate, duration
using SignalBase.Units: FrameQuant
export nframes, nchannels, sampletype, framerate, duration

module Units
    using SignalBase.Units
    export kframes, frames, Hz, s, kHz, ms, dB, °, rad
end
using .Units

@static if VERSION ≤ v"1.3"
    # patch in fix for clamp from Julia 1.3
    clamp(x,lo,hi) = max(min(x,hi),lo)
    clamp(::Missing,l,h) = missing
end

include("inflen.jl")
include("util.jl")

# signal definition
include("signal.jl")
include("sink.jl")
include("wrapping.jl")

# types of signals
include("numbers.jl")
include("arrays.jl")
include("functions.jl")

# various operators (transforms one signal into another)
include("cutting.jl")
include("appending.jl")
include("padding.jl")
include("filters.jl")
include("mapsignal.jl")
include("reformatting.jl")
include("ramps.jl")

function __init__()
    # TODO: use @require for AxisArrays

    @require WAV = "8149f6b0-98f6-5db9-b78f-408fbbb8ef88" begin
        include("WAV.jl")
    end

    @require FixedPointNumbers = "53c48c17-4a7d-5ca2-90c5-79b7896eea93" begin
        include("FixedPointNumbers.jl")
    end

    @require AxisArrays = "39de3d68-74b9-583c-8d2d-e117c070f3a9" begin
        include("AxisArrays.jl")
    end

    # extensions
    @require SampledSignals = "bd7594eb-a658-542f-9e75-4c4d8908c167" begin
        include("SampledSignals.jl")
    end

    @require LibSndFile = "b13ce0c6-77b0-50c6-a2db-140568b8d1a5" begin
        include("LibSndFile.jl")
    end

    @require DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"  begin
        include("DimensionalData.jl")
    end
end

end # module
