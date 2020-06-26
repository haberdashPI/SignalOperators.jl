using Statistics

abstract type WrappedSignal{T} <: AbstractSignal{T}
end

"""
    child(x)

Retrieve the signal wrapped by x of type `WrappedSignal`
"""
function child
end
SignalTrait(::Type{<:WrappedSignal}) = IsSignal()
EvalTrait(x::WrappedSignal) = EvalTrait(child(x))
nchannels(x::WrappedSignal) = nchannels(child(x))
framerate(x::WrappedSignal) = framerate(child(x))
nframes_helper(x::WrappedSignal) = nframes_helper(child(x))
duration(x::WrappedSignal) = duration(child(x))
root(x::WrappedSignal) = root(child(x))