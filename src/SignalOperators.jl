module SignalOperators
using Requires, DSP, LambdaFn, Unitful, Compat, PrettyPrinting, FillArrays

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

# extensions
# @require SampledSignals = "TODO" begin
#     include("SampledSignals.jl")
# end

# handle reading/writing to files
# using WAV
# include("WAV.jl")
function __init__()
    @require WAV = "8149f6b0-98f6-5db9-b78f-408fbbb8ef88" begin
        include("WAV.jl")
    end

    @require FixedPointNumbers = "53c48c17-4a7d-5ca2-90c5-79b7896eea93" begin
        include("FixedPointNumbers.jl")
    end
end

end # module
