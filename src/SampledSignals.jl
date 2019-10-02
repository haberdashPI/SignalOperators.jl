using .SampledSignals: SampleBuf

SignalTrait(::Type{<:SampleBuf{T}}) where T = IsSignal{T,Float64,Int}()
nsamples(x::SampleBuf,::IsSignal) = size(x,1)
nchannels(x::SampleBuf,::IsSignal) = size(x,2)
samplerate(x::SampleBuf,::IsSignal) = SampledSignals.samplerate(x)

@Base.propagate_inbounds function sampleat!(result,x::SampleBuf,i,j,check)
    writesink!(result,i,view(x,j,:))
end

function sink(x,sig::IsSignal{El},len::Number,::Type{<:SampleBuf}) where El
    result = SampleBuf{El}(len,nchannels(x))
    sink!(result,x)
end

