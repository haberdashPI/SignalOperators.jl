using .SampledSignals: SampleBuf

init_array_backend!(SampleBuf)
arraysignal(x,::Type{<:SampleBuf},fs) = SampleBuf(x,inHz(fs))
arraysignal(x::SampleBuf,::Type{<:SampleBuf},fs) = signal(x,fs)

function signal(x::SampleBuf,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $(inHz(fs)) Hz.")
    else
        x
    end
end
SignalTrait(::Type{<:SampleBuf{T}}) where T = IsSignal{T,Float64,Int}()
nsamples(x::SampleBuf) = size(x,1)
nchannels(x::SampleBuf) = size(x,2)
samplerate(x::SampleBuf) = SampledSignals.samplerate(x)

timeslice(x::SampleBuf,indices) = view(x,indices,:)
initsink(x,::Type{<:SampleBuf},len) =
    SampleBuf(channel_eltype(x),samplerate(x),len,nchannels(x))
