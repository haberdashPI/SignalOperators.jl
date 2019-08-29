
struct NumberSignal{T} <: AbstractSignal
    val::T
    samplerate::Float64
end
signal(val::Number,fs) = NumberSignal(val,Float64(inHz(fs)))
SignalTrait(x::NumberSignal{T}) where T = IsSignal{Tuple{T}}(x.samplerate)
struct Blank
end
const blank = Blank()
Base.iterate(x::NumberSignal,state=blank) = (x.val,),state
Base.Iterators.IteratorEltype(::Type{<:NumberSignal}) = Iterators.HasEltype()
Base.eltype(x::NumberSignal{T}) where T = Tuple{T}
Base.Iterators.IteratorSize(::Type{<:NumberSignal}) = Iterators.IsInfinite()
