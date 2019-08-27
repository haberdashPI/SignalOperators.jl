
struct NumberSignal{T}
    val::T
    samplerate::Float64
end
signal(val::Number,fs) = NumberSignal(val,Float64(inHz(fs)))
SignalTrait(x::NumberSignal) = IsSignal(x.samplerate)
struct Blank
end
const blank = Blank()
Base.iterate(x::NumberSignal,state=blank) = (x,),state
Base.IteratorEltype(::Type{<:NumberSignal}) = HasEltype()
Base.eltype(x::NumberSignal{T}) where T = Tuple{T}
Base.IteratorSize(::Type{<:NumberSignal}) = IsInfinite()

signal_eltype(x) = ntuple_T(eltype(samples(x)))
ntuple_T(x::NTuple{<:Any,T}) where T = T