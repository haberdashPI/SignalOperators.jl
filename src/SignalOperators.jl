module SignalOperators
using Requires, DSP, LambdaFn, Unitful, Compat, PrettyPrinting, FillArrays,
    FileIO

using PrettyPrinting: best_fit, indent, list_layout, literal, pair_layout

include("util.jl")

# signal definition
include("signal.jl")
include("inflen.jl")
include("sink.jl")
include("units.jl")
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

const curent_backend = Ref{Any}(Array)
const allowed_backends = [Array]
function init_array_backend!(::Type{T}) where T
    curent_backend[] = T
    push!(allowed_backends,T)
end
function set_array_backend!(::Type{T}) where T
    @assert T in allowed_backends
    curent_backend[] = T
end

function __init__()
    # TODO: use @require for AxisArrays
    init_array_backend!(AxisArray)

    @require WAV = "8149f6b0-98f6-5db9-b78f-408fbbb8ef88" begin
        include("WAV.jl")
    end

    @require FixedPointNumbers = "53c48c17-4a7d-5ca2-90c5-79b7896eea93" begin
        include("FixedPointNumbers.jl")
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
