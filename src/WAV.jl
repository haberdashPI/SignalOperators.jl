
using .WAV

sink(file::String) = x -> sink(x,file)
sink(x,file::String) = wavwrite(sink(x),file,Fs=samplerate(x))