module SignalOperators
using Require

# basic defintions
include("signal.jl")

# types of signals
include("arrays.jl")
include("functions.jl")
include("files.jl")

# handy utilities
include("util.jl")

# various operators
include("reformatting.jl")
include("cutting.jl")
include("extending.jl")
include("filters.jl")
include("binaryop.jl")
include("ramps.jl")

# extensions
# @require SampledSignals = "TODO" begin
#     include("SampledSignals.jl")
# end

# @require AxisArrays = "TODO" begin
#     include("AxisArrays.jl")
# end

end # module
