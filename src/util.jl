using Statistics

# computed signals have to implement there own version of some functions
# (e.g. resample) to avoid inefficient computations

struct DataSignal
end
struct ComputedSignal
end
EvalTrait(x) = DataSignal()
EvalTrait(x::AbstractSignal) = ComputedSignal()

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