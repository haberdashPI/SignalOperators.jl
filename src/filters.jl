export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_block_size = 2^12

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,@λ(digitalfilter(Lowpass(inHz(low),fs=_),method)),
        blocksize=default_block_size)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,@λ(digitalfilter(Highpass(inHz(high),fs=_),method)),
        blocksize=default_block_size)

bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,@λ(digitalfilter(Bandpass(inHz(low),inHz(high),fs=_),method)),
        blocksize=default_block_size)

bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),blocksize=default_block_size) = 
    filtersignal(x,@λ(digitalfilter(Bandstop(inHz(low),inHz(high),fs=_),method)),
        blocksize=default_block_size)

filtersignal(x,filter,method;kwds...) = 
    filtersignal(x,SignalTrait(x),x -> digitalfilter(filter,method);kwds...)
filtersignal(x,fn::Function;kwds...) = 
    filtersignal(x,SignalTrait(x),fn;kwds...)
filtersignal(x,h;kwds...) = 
    filtersignal(x,SignalTrait(x),x -> h;kwds...)
function filtersignal(x,::Nothing,args...;kwds...)
    filtersignal(signal(x),args...;kwds...)
end

# TODO: allow the filter to be applied iteratively to allow application of
# filter to infinite signal

# TODO: before we do that... define a very simple WrappedSignal object, instead
# of just sinking to data: this way we can allow missing samplerates to pass
# through filter operations

function filtersignal(x::Si,s::IsSignal,fn;blocksize,newfs=samplerate(x)) where {Si}
    T,Fn,Fs = float(channel_eltype(x)),typeof(fn),typeof(newfs)

    input = Array{channel_eltype(x.x)}(undef,1,1)
    ouptut = Array{channel_eltype(x)}(undef,0,0)
    h = x.fn(44.1kHz)
    dummy = FilterState(h,inHz(44.1kHz),0,0, si = [DSP._zerosi(h,input)])
    FilteredSignal{T,Si,Fn,typeof(newfs),typeof(dummy)}(x,fn,blocksize,newfs,Ref(dummy))
end
struct FilteredSignal{T,Si,Fn,Fs,St} <: WrappedSignal{Si,T}
    x::Si
    fn::Fn
    blocksize::Int
    samplerate::Fs
    state::Ref{St}
end
EvalTrait(x::FilteredSignal) = ComputedSignal()

mutable struct FilterState{H,S,T,St}
    h::H
    samplerate::Float64
    lastoffset::Int
    lastoutput::Int
    input::Matrix{S}
    ouptut::Matrix{T}
    si::St
end
function FilterState(x::FilteredSignal)
    h = x.fn(samplerate(fs))
    len = inputlength(h,x.blocksize)
    input = Array{channel_eltype(x.x)}(undef,len,nchannels(x))
    output = Array{channel_eltype(x)}(undef,x.blocksize,nchannels(x))
    lastoffset = Ref{Int}(0)
    lastoutput = Ref{Int}(size(output,1))
    si = (DSP._zerossi(h,input[:,1]) for _ in 1:nchannels(x))

    FilterState(h,lastoffset,lastoutput,input,output,si)
end

function tosamplerate(x::FilteredSignal,s::IsSignal,::ComputedSignal,fs)
    h = x.fn(fs)
    # is this a resampling filter?
    if samplerate(x) == samplerate(x.x)
        FilteredSignal(tosamplerate(x.x),x.fn,x.blocksize,fs)
    else
        tosamplerate(x.x,s,DataSignal(),fs)
    end
end
        
function nsamples(x::FilteredSignal)
    if ismissing(samplerate(x.x))
        missing
    elseif samplerate(x) == samplerate(x.x) 
        nsamples(x.x)
    else
        outputlength(x.fn(samplerate(x)),nsamples(x))
    end
end

struct FilterCheckpoint{St} <: AbstractCheckpoint
    n::Int
    state::St
end
checkindex(c::FilterCheckpoint) = c.n

inputlength(x::DSP.Filters.FIRKernel,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.FIRKernel,n) = DSP.outputlength(x,n)
inputlength(x,n) = n
outputlength(x,n) = n
function checkpoints(x::FilteredSignal,offset,len)
    filter(@λ(offset > _ > offset+len), [1:x.blocksize:(len-1); len]) |> 
    @λ(map(@λ(FilterCheckpoint(_,x.state[])),_))
end

struct NullBuffer
    len::Int
    ch::Int
end
Base.size(x::NullBuffer) = (x.len,x.ch)
writesink(x::NullBuffer,i,y) = y
Base.view(x::NullBuffer,i,j) = x

function beforecheckpoint(x::FilteredSignal,check,len)
    # initialize filtering state, if necessary
    if length(x.state[].output) == 0 || 
            x.state[].samplerate != samplerate(x)
        
        state = x.state[] = FilterState(x)

        if state.lastoffset > checkindex(check)
            state.lastoffset = 0
            state.lastoutput = 0
            for i in eachindex(state.si)
                state.si[i] .= 0
            end
        end
    end

    # refill buffer if necessary
    if state.lastoutput == size(state.output,1)
        # process any samples before offset that have yet to be processed
        if state.lastoffset < checkindex(check)
            sink!(NullBuffer(checkindex(check),nsamples(x)),x,
                SignalTrait(x),state.lastoffset,
                checkindex(check) - state.lastoffset)
        end

        # write child samples to input buffer
        sink!(view(state.input,1:min(size(state.input,1),len),:),
            x.x,SignalTrait(x.x),len)
        # pad any unwritten samples
        state.input[len+1:end,:] .= 0

        # filter the input to the output buffer
        for ch in 1:size(state.output,2)
            filt!(view(state.output,:,ch),state.h,view(state.input,:,ch),
                state.si[ch])
        end

        state.lastoutput = 0
        state.lastoffset += size(state.output,1)
    end
end
function aftercheckpoint(x::FilteredSignal,check,len)
    x.state[].lastoutput += len
end

@Base.propagate_inbounds function sampleat!(result,x::FilteredSignal,
        sig,i,j,check)

    writesink(result,i,view(x.output,j-check.state.lastoutput,:))
end

# TODO: create an online version of normpower?
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs)
end