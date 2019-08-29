using .SampledSignals: SampleBuf

function SignalTrait(x::SampleBuf)
    IsSignal{nchannels(x)}(SampledSignals.samplerate(x))
end
samples(x::SampleBuf) = TimeSlices{nchannels(x)}(x)

SampleBuf(x::AbstractSignal) = SampleBuf(sink(x),samplerate(x))
SampleBuf(x::MetaArray{<:Any,IsSignal}) = SampleBuf(sink(x),samplerate(x))