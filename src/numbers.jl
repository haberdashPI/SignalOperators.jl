struct NumberSignal{T,S} <: AbstractSignal
    val::T
    samplerate::S
end
signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,Nothing}()

nchannels(x::NumberSignal,::IsSignal) = 1
nsamples(x::NumberSignal,::IsSignal) = nothing
samplerate(x::NumberSignal,::IsSignal) = x.samplerate 

tosamplerate(x::NumberSignal,::IsSignal,::ComputedSignal,fs=missing) = 
    NumberSignal(x,fs)

@Base.propagate_inbounds signal_setindex!(result,ri,x::NumberSignal,xi) = 
    result[ri,:] = x.val