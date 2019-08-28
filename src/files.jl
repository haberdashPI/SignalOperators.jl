
# signals can be filenames
function signal(x::String,fs=nothing)
    x,_fs = load(x)
    if !checksamplerate(inHz(fs),_fs)
        error("Expected file $x to have samplerate $fs.")
    end
    signal(x,_fs)
end