using .WAV

sink(to::String;kwds...) = x -> sink(x,to;kwds...)
function sink(x,to::String;duration=missing,
    samplerate=SignalOperators.samplerate(x))

    data = sink(x,duration=duration,samplerate=samplerate)
    wavwrite(data,to,Fs=round(Int,SignalOperators.samplerate(data)))
end

function signal(x::String,fs::Union{Missing,Number}=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs. If you wish to convert",
              " the sample rate, you can use `tosamplerate`.")
    end
    signal(x,_fs)
end