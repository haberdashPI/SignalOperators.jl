using .SampledSignals: SampleBuf

SignalTrait(x::SampleBuf{T}) where T = 
    IsSignal{T,Float64,Int}(SampledSignals.samplerate(x),size(x,1))
SignalTrait(::Type{<:SampleBuf{T}}) where T = IsSignal{T,Float64,Int}
nchannels(x::SampleBuf,::IsSigal) = size(x,2)
samples(x::SampleBuf,::IsSignal) = TimeSlices(x)

SampleBuf(x::AbstractSignal) = SampleBuf(sink(x),samplerate(x))
SampleBuf(x::MetaArray{<:Any,IsSignal}) = SampleBuf(sink(x),samplerate(x))