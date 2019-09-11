
# using .WAV

sink(to::String;kwds...) = x -> sink(x,to;kwds...)
function sink(x,to::String;length=missing,
    samplerate=SignalOperators.samplerate(x))

    x = signal(x,samplerate)
    length = coalesce(length,nsamples(x))

    data = sink(x,length=length,samplerate=samplerate)
    wavwrite(data,to,Fs=round(Int,inHz(samplerate)))
end

function signal(x::String,fs::Union{Missing,Number}=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs. If you wish to convert",
              " the sample rate, you can use `tosamplerate`.")
    end
    signal(x,_fs)
end