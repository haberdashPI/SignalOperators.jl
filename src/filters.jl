export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order)) = 
    filtersignal(x,Lowpass(inHz(low),fs=samplerate(x)),method)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order)) = 
    filtersignal(x,Highpass(inHz(high),fs=samplerate(x)),method)

bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order)) = 
    filtersignal(x,Bandpass(inHz(low),inHz(high),fs=samplerate(x)),method)

bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order)) = 
    filtersignal(x,Bandstop(inHz(low),inHz(high),fs=samplerate(x)),method)

filtersignal(x,filter,method) = filtersignal(x,SignalTrait(x),filter,method)
function filtersignal(x,::Nothing,args...)
    error("Value is not a signal $x.")
end

# TODO: allow the filter to be applied iteratively to allow application of
# filter to infinite signal
filtersignal(x,s::IsSignal,f,m) = filtersignal(x,s,digitalfilter(f,m))
function filtersignal(x,s::IsSignal,h)
    data = sink(x)
    mapreduce(hcat,1:nchannels(x)) do ch
        filt(h,data[:,ch])
    end |> @λ(signal(_,s.samplerate))
end

# TODO: allow this to be applied iteratively for application to infinite signal
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs*Hz)
end