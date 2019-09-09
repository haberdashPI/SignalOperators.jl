export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_blocksize = 2^12

lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Lowpass(inHz(low),fs=inHz(_)),method)),
        blocksize=default_blocksize)

highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Highpass(inHz(high),fs=inHz(_)),method)), 
        blocksize=default_blocksize)

bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Bandpass(inHz(low),inHz(high),fs=inHz(_)),
        method)), blocksize=default_blocksize)

bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Bandstop(inHz(low),inHz(high),fs=inHz(_)), 
        method)), blocksize=default_blocksize)

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

resolve_filter(x) = DF2Filter(x)
resolve_filter(x::FIRFilter) = x
function filtersignal(x::Si,s::IsSignal,fn;blocksize,newfs=samplerate(x)) where {Si}
    T,Fn,Fs = float(channel_eltype(x)),typeof(fn),typeof(newfs)

    input = Array{channel_eltype(x)}(undef,1,1)
    output = Array{float(channel_eltype(x))}(undef,0,0)
    h = resolve_filter(fn(44.1kHz))
    dummy = FilterState(h,inHz(44.1kHz),0,0,input,output)
    FilteredSignal{T,Si,Fn,typeof(newfs),typeof(dummy)}(x,fn,blocksize,newfs,Ref(dummy))
end
struct FilteredSignal{T,Si,Fn,Fs,St} <: WrappedSignal{Si,T}
    x::Si
    fn::Fn
    blocksize::Int
    samplerate::Fs
    state::Ref{St}
end
childsignal(x::FilteredSignal) = x.x
EvalTrait(x::FilteredSignal) = ComputedSignal()

mutable struct FilterState{H,S,T}
    h::H
    samplerate::Float64
    lastoffset::Int
    lastoutput::Int
    input::Matrix{S}
    output::Matrix{T}
    function FilterState(h::H,fs::Float64,lastoffset::Int,lastoutput::Int,
        input::Matrix{S},output::Matrix{T}) where {H,S,T}
    
        new{H,S,T}(h,fs,lastoffset,lastoutput,input,output)
    end
end
function FilterState(x::FilteredSignal)
    h = x.fn(samplerate(x))
    len = inputlength(h,x.blocksize)
    input = Array{channel_eltype(x.x)}(undef,len,nchannels(x))
    output = Array{channel_eltype(x)}(undef,x.blocksize,nchannels(x))
    lastoffset = 0
    lastoutput = size(output,1)

    FilterState(h,samplerate(x),lastoffset,lastoutput,input,output)
end

function tosamplerate(x::FilteredSignal,s::IsSignal,::ComputedSignal,fs;
    blocksize)

    h = x.fn(fs)
    # is this a resampling filter?
    if samplerate(x) != samplerate(x.x)
        tosamplerate(x.x,s,DataSignal(),fs)
    else
        FilteredSignal(tosamplerate(x.x),x.fn,x.blocksize,fs)
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

function reset!(x::DF2TFilter) 
    x.state .= zero(eltype(x.state))
    x
end
function reset!(x::FIRFilter)
    x.history .= zero(eltype(x.history))
    x
end

inputlength(x::DSP.Filters.FIRKernel,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.FIRKernel,n) = DSP.outputlength(x,n)
inputlength(x,n) = n
outputlength(x,n) = n
function checkpoints(x::FilteredSignal,offset,len)
    # initialize filtering state, if necessary
    state = if length(x.state[].output) == 0 || 
            x.state[].samplerate != samplerate(x)
        
        x.state[] = FilterState(x)
    else
        x.state[]
    end

    if state.lastoffset > offset
        state.lastoffset = 0
        state.lastoutput = size(state.output,1)
        reset!(state.h)
    end

    # create checkpoints
    checks = filter(@λ(offset < _ ≤ offset+len), [1:x.blocksize:len; len+1])
    if checks[1] != offset+1
        pushfirst!(checks,offset+1)
    end
    if checks[end] != offset+len+1
        push!(checks,offset+len+1)
    end
    map(@λ(FilterCheckpoint(_,state)),checks)
end

struct NullBuffer
    len::Int
    ch::Int
end
Base.size(x::NullBuffer) = (x.len,x.ch)
Base.size(x::NullBuffer,n) = (x.len,x.ch)[n]
writesink(x::NullBuffer,i,y) = y
Base.view(x::NullBuffer,i,j) = x

function beforecheckpoint(x::FilteredSignal,check,len)
    # refill buffer if necessary
    state = check.state
    if state.lastoutput == size(state.output,1)
        # process any samples before offset that have yet to be processed
        if state.lastoffset < checkindex(check)-1
            sink!(NullBuffer(checkindex(check) - state.lastoffset,nchannels(x)),
                x,SignalTrait(x),state.lastoffset)
        end

        # write child samples to input buffer
        sink!(view(state.input,1:min(size(state.input,1),len),:),
            x.x,SignalTrait(x.x),len)
        @info("Finished inner sink!")
        # pad any unwritten samples
        state.input[len+1:end,:] .= 0

        # filter the input to the output buffer
        for ch in 1:size(state.output,2)
            filt!(view(state.output,:,ch),state.h,view(state.input,:,ch))
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

    writesink(result,i,view(check.state.output,j-check.state.lastoutput,:))
end

# TODO: create an online version of normpower?
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs*Hz)
end