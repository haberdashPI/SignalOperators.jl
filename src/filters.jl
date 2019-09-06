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
    filter_state::Ref{St}
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

struct FilterCheckpoint <: AbstractCheckpoint
    n::Int
end
checkindex(c::FilterCheckpoint) = c.n

inputlength(x::DSP.Filters.FIRKernel,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.FIRKernel,n) = DSP.outputlength(x,n)
inputlength(x,n) = n
outputlength(x,n) = n
function checkpoints(x::FilteredSignal,offset,len)
    map(FilterCheckpoint,[1:x.blocksize:(len-1); len])
end

struct NullBuffer
    ch::Int
end
Base.size(x::NullBuffer) = (1,x.ch)
writesink(x::NullBuffer,i,y) = y
Base.view(x::NullBuffer,i,j) = x

function sinkchunk!(result,off,x::FilteredSignal,sig::IsSignal,check,last)

    # initialize filtering state, if necessary
    if length(x.filter_state[].output) == 0 || 
            x.filter_state[].samplerate != samplerate(x)
        
        state = x.filter_state[] = FilterState(x)

        if state.lastoffset > checkindex(check)
            state.lastoffset = 0
            state.lastoutput = 0
            for i in eachindex(state.si)
                state.si[i] .= 0
            end
        end
    end

    sinkchunk!(result,off,x,sig,check,last,state)
end
function sinkchunk(result,off,x::FilteredSignal,sig::IsSignal,
        check,last,state::FilterState)

    written = 0
    null_buffer = NullBuffer(size(result,2))
    total = checkindex(check) - last + 1
    while written < total
        # determine the destination and maximum number of samples to write
        # to that destination. The null_buffer discards samples before the
        # offset
        dest = if state.lastoffset < checkindex(check) 
            max_write = state.lastoffset - checkindex(check)
            null_buffer 
        else 
            max_write = total - written
            result
        end

        # generate more output from the child signal, as needed
        if state.lastoutput == size(state.output,1)
            # read singal into input buffer
            max_input = nsamples(x.x) - state.lastoffset
            to_write = min(size(state.input,1),max_output) 
            sink!(@views(state.input[1:to_write,:]),x.x,
                SignalTrait(x.x),state.lastoffset)
            state.lastoffset += to_write
            state.input[to_write+1:end,:] .= 0

            # filter the input to the output buffer
            for ch in 1:size(state.output,2)
                filt!(view(state.output,:,ch),state.h,view(state.input,:,ch),
                    state.si[ch])
            end
        end

        # write the output to the destination
        n = min(
            max_write,
            size(state.output,1) - state.lastoutput[]
        )
        for ch in size(dest,2)
            copyto!(view(dest,:,ch),written+1,view(state.output,:,ch),
                state.lastoffset[]+1, n)
        end
        state.lastoutput += n
        state.lastoffset += n
        dest == result && (written += n)
    end
end

# TODO: create an online version of normpower?
function normpower(x)
    fs = samplerate(x)
    x = sink(x)
    x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs)
end