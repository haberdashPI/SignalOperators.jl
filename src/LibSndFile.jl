using .LibSndFile

@info "Loading LibSndFile backend for SignalOperators."

for fmt in LibSndFile.supported_formats
    if fmt != DataFormat{:WAV}
        @eval function load_signal(::$fmt,filename,fs=missing)
            signal(load(filename),fs)
        end
        @eval function save_signal(::$fmt,filename,x,len)
            data,sr = sink(x,Array,duration=len*frames)
            save(filename,data,samplerate=sr)
        end
    end
end