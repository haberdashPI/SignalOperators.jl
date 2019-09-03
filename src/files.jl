
# signals can be filenames
function signal(x::String,fs=missing)
    x,_fs = load(x)
    if !isconsistent(fs,_fs)
        error("Expected file $x to have samplerate $fs.")
    end
    signal(x,_fs)
end
