using .SampledSignals: SampleBuf

function SignalTrait(x::SampleBuf)
    IsSignal{nchannels(x)}(SampledSignals.samplerate(x))
end
samples(x::SampleBuf) = TimeSlices{nchannels(x)}(x)

SampleBuf(x::AbstractSignal) = SampleBuf(asarray(x),samplerate(x))
SampleBuf(x::MetaArray{<:Any,IsSignal}) = SampleBuf(asarray(x),samplerate(x))