export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_block_size = 2^12


lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,Lowpass(inHz(low),fs=samplerate(x)),method,
    blocksize=default_block_size)

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

filtersignal(x,s::IsSignal,f,m;blocksize=default_block_size) = 
    filtersignal(x,s,digitalfilter(f,m),blocksize=blocksize)
function filtersignal(x::Si,s::IsSignal,h::H;blocksize) where {Si,H}
    n = DSP.inputlength(h,x.blocksize)
    buffer = Array{channel_eltype(x)}(undef,n,nchannels(x))
    si = (DSP._zerossi(h,buffer) for _ in 1:nchannels(x))

    FilteredSignal{channel_eltype(x),Si,H}(x,h,buffer,si)
end
struct FilteredSignal{T,Si,H,A} <: WrappedSignal{Si,T}
    x::Si
    h::H
    input::Matrix{T}
    si::A
end

# TODO: report this as a ComputedSignal and implement tosamplerate
# at the same time, I should have the filters computed lazily
EvalTrait(x::FilteredSignal) = DataSignal()

struct FilterCheckpoint
    n::Int
    firstoffset::Int
end
function checkpoints(x::FilteredSignal,offset,len)
    for i in eachindex(x.si)
        x.si[i] .= 0
    end

    n = size(x.buffer,1)
    mapreduce([1:x.blocksize:(len-1); len]) do i
        FilterCheckpoint(i+offset,i == 1 ? offset : 0)
    end
end

struct NullBuffer
    n::Int
end
Base.size(x::NullBuffer) = (x.n,1)
writesink(x::NullBuffer,i,y) = y

function sinkchunk!(result::AbstractArray,x::FilteredSignal,sig::IsSignal,
    offset,check,last)

    # if were at an offset, we still have to filter all of the samples
    # before the offset, so run sink! up until the offset
    if check.firstoffset > 0   
        sink!(NullBuffer(offset),x,SignalTrait(x),0)
    end

    # now that the filter state is properly initialized
    # apply the filter to the remaining samples
    k = min(size(x.buffer,1),last-checkindex(check)+1)
    @views begin 
        sink!(x.buffer[1:k,:],x.x,SignalTrait(x.x),check.n)
        for ch in 1:nchannels(x)
            filter!(result[(checkindex(check):last) .- offset,ch],x.h,
                x.buffer[1:k,ch])
        end
    end
end

# TODO: create an online version of normpower?
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs)
end