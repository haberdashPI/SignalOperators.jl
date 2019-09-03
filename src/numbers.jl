struct NumberSignal{T,S} <: AbstractSignal
    val::T
    samplerate::S
end
signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,Nothing}()
struct Blank
end
const blank = Blank()
Base.iterate(x::NumberSignal,state=blank) = (x.val,),state
Base.Iterators.IteratorEltype(::Type{<:NumberSignal}) = Iterators.HasEltype()
Base.eltype(::Type{<:NumberSignal{T}}) where T = Tuple{T}
Base.Iterators.IteratorSize(::Type{<:NumberSignal}) = Iterators.IsInfinite()

nchannels(x::NumberSignal,::IsSignal) = 1
nsamples(x::NumberSignal,::IsSignal) = nothing
samplerate(x::NumberSignal,::IsSignal) = x.samplerate 

tosamplerate(x::NumberSignal,::IsSignal,::ComputedSignal,fs=missing) = 
    NumberSignal(x,fs)