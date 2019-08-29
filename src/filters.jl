export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;method=Butterworth(order),order=5) = 
    filter_helper(x,Lowpass(inHz(low),samplerate(x)),method)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;method=Butterworth(order),order=5) = 
    filter_helper(x,Highpass(inHz(high),samplerate(x)),method)

bandpass(low,high;kwds...) = x->highpass(x,low,high;kwds...)
bandpass(x,low,high;method=Butterworth(order),order=5) = 
    filter_helper(x,Bandpass(inHz(high),samplerate(x)),method)

bandstop(low,high;kwds...) = x->highpass(x,low,high;kwds...)
bandstop(x,low,high;method=Butterworth(order),order=5) = 
    filter_helper(x,Bandstop(inHz(high),samplerate(x)),method)

filtersignal(x,filter,method) = filtersignal(x,SignalTrait(x),filter,method)
function filtersignal(x,::Nothing,args...)
    error("Value is not a signal $x.")
end

# TODO: allow the filter to be applied iteratively to allow application of
# filter to infinite signal
filtersignal(x,s::IsSignal,f,m) = filtersignal(x,s,digitalfilter(f,m))
function filtersignal(x,s::IsSignal,h)
    result = mapreduce(hcat,sink(x)) do ch
        filt(h,ch)
    end

    signal(result,s.samplerate)
end

# TODO: allow this to be applied iteratively for application to infinite signal
function normpower(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1))
end