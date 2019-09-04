export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_block_size = 4096

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=0) = 
    filtersignal(x,Lowpass(inHz(low),fs=samplerate(x)),method,
    blocksize=0)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=0) = 
    filtersignal(x,Highpass(inHz(high),fs=samplerate(x)),method,
        blocksize=0)

bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),blocksize=0) = 
    filtersignal(x,Bandpass(inHz(low),inHz(high),fs=samplerate(x)),method,
        blocksize=0)

bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),blocksize=0) = 
    filtersignal(x,Bandstop(inHz(low),inHz(high),fs=samplerate(x)),method,
        blocksize=0)

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

filtersignal(x,s::IsSignal,f,m;blocksize=0) = 
    filtersignal(x,s,digitalfilter(f,m),blocksize=blocksize)
function filtersignal(x::Si,s::IsSignal,h::H;blocksize) where {Si,H}
    FilteredSignal{channel_eltype(Si),Si,H}(x,h,blocksize)
end
struct FilteredSignal{T,Si,H} <: WrappedSignal{Si,T}
    x::Si
    h::H
    blocksize::Int
end
block_length(x::FilteredSignal) = Block(x.blocksize)
function init_block(result,x::FilteredSignal,::IsSignal,offset,block) 
    buffer = init_children(x,DSP.inputlength(x.h,block.max),block)
    si = (DSP._zerossi(x.h,buffer) for _ in 1:nchannels(x.x))
    child_state = init_block(result,x.x,SignalTrait(x.x),offset,block)
    (buffer,si,child_state)
end

function sinkblock!(result::AbstractArray,x::FilteredSignal,sig::IsSignal,
        (buffer,si,child_state), offset::Number)
    
    # problem: inlen could be > size(buffer,1)
    inlen = DSP.inputlength(x.h,result)
    sinkblock!(@views(buffer[1:inlen,:]),x.x,SignalTrait(x.x), child_state, offset)
    for ch in 1:nchannels(x)
        @views(filt!(result[:,ch],x.h,buffer[1:inlen,ch],si[ch]))
    end 
end

# TODO: allow this to be applied iteratively for application to infinite signal
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs)
end