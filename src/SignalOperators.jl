module SignalOperators
using Requires
using DSP

# basic defintions
include("signal.jl")

# types of signals
include("numbers.jl")
include("arrays.jl")
include("functions.jl")
include("files.jl")

# handy internal utilities
include("util.jl")

# handling of units
include("units.jl")

# various operators
include("cutting.jl")
include("extending.jl")
include("filters.jl")
include("binaryop.jl")
include("reformatting.jl")
include("ramps.jl")

# extensions
# @require SampledSignals = "TODO" begin
#     include("SampledSignals.jl")
# end

# @require AxisArrays = "TODO" begin
#     include("AxisArrays.jl")
# end

end # module
