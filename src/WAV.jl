
using .WAV

sink(to::String;kwds...) = x -> sink(x,to;kwds...)
sink(x,to::String;length=nsamples(x)*frames,samplerate=SignalOperators.samplerate(x)) = 
    wavwrite(sink(x,length=length,samplerate=samplerate),to,Fs=samplerate)

function signal(x::String,fs::Union{Missing,Number}=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs. If you wish to convert",
              " the sample rate, you can use `tosamplerate`.")
    end
    signal(x,_fs)
end