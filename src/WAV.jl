using .WAV

function save_signal(::DataFormat{:WAV},filename,x,len)
    data = sink(x,duration=len*samples)
    wavwrite(data,filename,Fs=round(Int,SignalOperators.samplerate(data)))
end

function load_signal(::DataFormat{:WAV},x,fs=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs. If you wish to convert",
              " the sample rate, you can use `tosamplerate`.")
    end
    signal(x,_fs)
end