
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

filter_helper(x,filter,method) = filter_helper(x,SignalTrait(x),filter,method)
function filter_helper(x,::Nothing,args...)
    error("Value is not a signal $x.")
end
function filter_helper(x,::IsSignal,filter,method)
    H = digitalfilter(filter,method)
    data = asarray(x)
    mapreduce(hcat,1:size(data,2)) do ch
        filtfilt(H,data[:,ch])
    end
end

function normpower(x)
    x = asarray(x)
    x ./ sqrt.(mean(x.^2,dims=1))
end