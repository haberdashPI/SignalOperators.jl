
using .WAV

sink(x,to::String;length=nsamples(x)*frames,samplerate=samplerate(x)) = 
    wavwrite(sink(x),file,Fs=samplerate(x))

function signal(x::String,fs=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs. If you wish to convert",
              " the sample rate, you can use `tosamplerate`.")
    end
    signal(x,_fs)
end