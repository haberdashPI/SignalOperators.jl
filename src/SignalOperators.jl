module SignalOperators
using Requires, DSP, LambdaFn, Unitful, Compat

# generic signal definitions
include("signal.jl")

# handling of units
include("units.jl")

# definition of wrapped signals
include("wrapping.jl")

# types of signals
include("numbers.jl")
include("arrays.jl")
include("functions.jl")

# various operators (transforms one signal into another)
include("cutting.jl")
include("extending.jl")
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
end

end # module
