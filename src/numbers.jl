struct NumberSignal{T,S} <: AbstractSignal{T}
    val::T
    samplerate::S
end
"""

## Numbers

Numbers can be treated as infinite length, constant signals of unknown
sample rate.

"""
signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
signal(val::Unitful.Gain,::Nothing,fs) = 
    NumberSignal(uconvertrp(NoUnits,val),inHz(Float64,fs))

SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,InfiniteLength}()

nchannels(x::NumberSignal,::IsSignal) = 1
nsamples(x::NumberSignal,::IsSignal) = inflen
samplerate(x::NumberSignal,::IsSignal) = x.samplerate 

tosamplerate(x::NumberSignal,::IsSignal,::ComputedSignal,fs=missing;blocksize) = 
    NumberSignal(x.val,fs)

@Base.propagate_inbounds function sampleat!(result,x::NumberSignal,
    ::IsSignal,i::Number,j::Number,check)

    writesink!(result,i,x.val)
end
