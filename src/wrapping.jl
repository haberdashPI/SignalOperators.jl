using Statistics

abstract type WrappedSignal{C,T} <: AbstractSignal{T}
end

"""
    childsignal(x)

Retrieve the signal wrapped by x of type `WrappedSignal`
"""
function childsignal
end
SignalTrait(::Type{<:WrappedSignal{C}}) where C = SignalTrait(C)
EvalTrait(x::WrappedSignal) = EvalTrait(childsignal(x))
nchannels(x::WrappedSignal,::IsSignal) = nchannels(childsignal(x))
samplerate(x::WrappedSignal,::IsSignal) = samplerate(childsignal(x))