using .SampledSignals: SampleBuf

function SignalTrait(x::SampleBuf)
    IsSignal(SampledSignals.samplerate(x))
end
samples(x::SampleBuf) = TimeSlices{size(x,2)}(x)
nsamples(x::SampleBuf,::IsSignal) = size(x,1)
signal_length(x::SampleBuf,::IsSignal) = (size(x,1)-1)*frames