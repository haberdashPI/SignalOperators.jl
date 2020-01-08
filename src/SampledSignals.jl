using .SampledSignals: SampleBuf

function Signal(x::SampleBuf,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,framerate(x))
        error("Signal expected to have frame rate of $(inHz(fs)) Hz.")
    else
        x
    end
end
SignalTrait(::Type{<:SampleBuf{T}}) where T = IsSignal{T,Float64,Int}()
nframes(x::SampleBuf) = size(x,1)
nchannels(x::SampleBuf) = size(x,2)
framerate(x::SampleBuf) = SampledSignals.samplerate(x)
channeltype(x::SampleBuf) = eltype(x)

timeslice(x::SampleBuf,indices) = view(x,indices,:)
initsink(x,::Type{<:SampleBuf}) =
    SampleBuf(channel_eltype(x),framerate(x),nframes(x),nchannels(x))
SampleBuf(x::AbstractSignal) = sink(x,SampleBuf)