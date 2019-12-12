using .SampledSignals: SampleBuf

function signal(x::SampleBuf,::IsSignal,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
    else
        x
    end
end
SignalTrait(::Type{<:SampleBuf{T}}) where T = IsSignal{T,Float64,Int}()
nsamples(x::SampleBuf) = size(x,1)
nchannels(x::SampleBuf) = size(x,2)
samplerate(x::SampleBuf) = SampledSignals.samplerate(x)

function nextblock(x::SampleBuf,maxlen,skip,block = ArrayBlock(view(x,1:0),0))
    offset = block.state + nsamples(block)
    if offset < nsamples(x)
        len = min(maxlen,nsamples(x)-offset)
        ArrayBlock(view(x,offset .+ (1:len),:),offset)
    end
end

function sink(x,::Type{<:SampleBuf};kwds...)
    x,n = process_sink_params(x;kwds...)
    result = SampleBuf(channel_eltype(x),samplerate(x),n,nchannels(x))
    sink!(result,x)
end