export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const defeault_block_size = 4096

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=defeault_block_size) = 
    filtersignal(x,Lowpass(inHz(low),fs=samplerate(x)),method,
    blocksize=defeault_block_size)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,Highpass(inHz(high),fs=samplerate(x)),method,
        blocksize=default_block_size)

bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,Bandpass(inHz(low),inHz(high),fs=samplerate(x)),method,
        blocksize=default_block_size)

bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,Bandstop(inHz(low),inHz(high),fs=samplerate(x)),method,
        blocksize=default_block_size)

filtersignal(x,filter,method;kwds...) = 
    filtersignal(x,SignalTrait(x),filter,method;kwds...)
function filtersignal(x,::Nothing,args...;kwds...)
    filtersignal(signal(x),args...;kwds...)
end

# TODO: allow the filter to be applied iteratively to allow application of
# filter to infinite signal

# TODO: before we do that... define a very simple WrappedSignal object, instead
# of just sinking to data: this way we can allow missing samplerates to pass
# through filter operations

filtersignal(x,s::IsSignal,f,m;blocksize=defeault_block_size) = 
    filtersignal(x,s,digitalfilter(f,m),blocksize=blocksize)
function filtersignal(x::Si,s::IsSignal,h::H;blocksize) where {Si,H}
    FilteredSignal{channel_eltype(Si),Si,H}(x,h,blocksize)
end
struct FilteredSignal{T,Si,H} <: WrappedSignal{Si,T}
    x::Si
    h::H
    blocksize::Int
end
function signal_indices(x::FilteredSignal,ri::Range,xi::Range)
    Iterators.partition(ri,x.blocksize), Iterators.partition(xi,x.blocksize)
end
function signal_indices
    data = sink(x)
    mapreduce(hcat,1:nchannels(x)) do ch
        filt(h,data[:,ch])
    end |> @λ(signal(_,s.samplerate))
end

# TODO: allow this to be applied iteratively for application to infinite signal
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs)
end