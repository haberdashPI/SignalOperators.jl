using Statistics

abstract type WrappedSignal{C,T} <: AbstractSignal{T}
end

"""
    child(x)

Retrieve the signal wrapped by x of type `WrappedSignal`
"""
function child
end
SignalTrait(::Type{<:WrappedSignal{C}}) where C = SignalTrait(C)
EvalTrait(x::WrappedSignal) = EvalTrait(child(x))
nchannels(x::WrappedSignal) = nchannels(child(x))
framerate(x::WrappedSignal) = framerate(child(x))
nframes(x::WrappedSignal) = nframes(child(x))
unextended_nframes(x::WrappedSignal) = unextended_nframes(child(x))
duration(x::WrappedSignal) = duration(child(x))
root(x::WrappedSignal) = root(child(x))