using .WAV

function save_signal(::DataFormat{:WAV},filename,x,len)
    data = sink(x,duration=len*frames)
    wavwrite(data,filename,Fs=round(Int,SignalOperators.framerate(data)))
end

function load_signal(::DataFormat{:WAV},x,fs=missing)
    x,_fs = wavread(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have framerate $fs. If you wish to convert",
              " the frame rate, you can use `ToFramerate`.")
    end
    Signal(x,_fs)
end