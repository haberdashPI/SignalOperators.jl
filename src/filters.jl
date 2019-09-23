export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_blocksize = 2^12

"""
    lowpass(x,low;[order=5],[method=Butterworth(order)],[blocksize])

Apply a lowpass filter to x at the given cutoff frequency (`low`). 
See [`filtersignal`](@ref) for details on `blocksize`.
"""
lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Lowpass(inHz(low),fs=inHz(_)),method)),
        blocksize=blocksize)

"""
    highpass(x,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a highpass filter to x at the given cutoff frequency (`low`). 
See [`filtersignal`](@ref) for details on `blocksize`.
"""
highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Highpass(inHz(high),fs=inHz(_)),method)), 
        blocksize=blocksize)

"""
    bandpass(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandpass filter to x at the given cutoff frequencies (`low` and `high`). 
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Bandpass(inHz(low),inHz(high),fs=inHz(_)),
        method)), blocksize=blocksize)

"""
    bandstop(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandstop filter to x at the given cutoff frequencies (`low` and `high`). 
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) = 
    filtersignal(x, @λ(digitalfilter(Bandstop(inHz(low),inHz(high),fs=inHz(_)), 
        method)), blocksize=blocksize)

"""
    filtersignal(x,h;[blocksize])

Apply the given filter `h` (from [`DSP`](https://github.com/JuliaDSP/DSP.jl))
to signal `x`. 

## Blocksize

Blocksize determines the size of the buffer used when computing intermediate
values of the filter. It defaults to 4096. It need not normally be adjusted.

"""
filtersignal(h;blocksize=default_blocksize) = 
    x -> filtersignal(x,h;blocksize=blocksize)
filtersignal(x,fn::Function;kwds...) = 
    filtersignal(x,SignalTrait(x),fn;kwds...)
filtersignal(x,h;kwds...) = 
    filtersignal(x,SignalTrait(x),x -> h;kwds...)
function filtersignal(x,::Nothing,args...;kwds...)
    filtersignal(signal(x),args...;kwds...)
end

resolve_filter(x) = DSP.Filters.DF2TFilter(x)
resolve_filter(x::FIRFilter) = x
function filtersignal(x::Si,s::IsSignal,fn;blocksize,newfs=samplerate(x)) where {Si}
    FilteredSignal(x,fn,blocksize,newfs)
end
struct FilteredSignal{T,Si,Fn,Fs} <: WrappedSignal{Si,T}
    signal::Si
    fn::Fn
    blocksize::Int
    samplerate::Fs
end
function FilteredSignal(signal::Si,fn::Fn,blocksize::Number,newfs::Fs) where {Si,Fn,Fs}
    T = float(channel_eltype(signal))
    FilteredSignal{T,Si,Fn,Fs}(signal,fn,Int(blocksize),newfs)
end
SignalTrait(x::Type{T}) where {S,T <: FilteredSignal{<:Any,S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:FilteredSignal{T}},::IsSignal{<:Any,Fs,L}) where {T,Fs,L} =
    IsSignal{T,Fs,L}()
childsignal(x::FilteredSignal) = x.signal
samplerate(x::FilteredSignal) = x.samplerate
EvalTrait(x::FilteredSignal) = ComputedSignal()

mutable struct FilterState{H,Fs,S,T}
    h::H
    samplerate::Fs
    lastoffset::Int
    lastoutput::Int
    availableoutput::Int
    input::Matrix{S}
    output::Matrix{T}
    function FilterState(h::H,fs::Fs,lastoffset::Int,lastoutput::Int,
        availableoutput::Int,input::Matrix{S},output::Matrix{T}) where {H,Fs,S,T}
    
        new{H,Fs,S,T}(h,fs,lastoffset,lastoutput,availableoutput,input,output)
    end
end
function FilterState(x::FilteredSignal)
    h = resolve_filter(x.fn(samplerate(x)))
    len = inputlength(h,x.blocksize)
    input = Array{channel_eltype(x.signal)}(undef,len,nchannels(x))
    output = Array{channel_eltype(x)}(undef,x.blocksize,nchannels(x))
    availableoutput = 0
    lastoffset = 0
    lastoutput = 0

    FilterState(h,float(samplerate(x)),lastoffset,lastoutput,availableoutput,
        input,output)
end

function tosamplerate(x::FilteredSignal,s::IsSignal{<:Any,<:Number},::ComputedSignal,fs;
blocksize)
    # is this a non-resampling filter?
    if samplerate(x) == samplerate(x.signal)
        FilteredSignal(tosamplerate(x.signal,fs,blocksize=blocksize),
            x.fn,x.blocksize,fs)
    else
        tosamplerate(x.signal,s,DataSignal(),fs,blocksize=blocksize)
    end
end
function tosamplerate(x::FilteredSignal,::IsSignal{<:Any,Missing},__ignore__,fs;
        blocksize)
    FilteredSignal(tosamplerate(x.signal,fs,blocksize=blocksize),
        x.fn,x.blocksize,fs)
end
        
function nsamples(x::FilteredSignal)
    if ismissing(samplerate(x.signal))
        missing
    elseif samplerate(x) == samplerate(x.signal) 
        nsamples(x.signal)
    else
        ceil(Int,nsamples(x.signal)*samplerate(x)/samplerate(x.signal))
    end
end

struct FilterCheckpoint{St} <: AbstractCheckpoint
    n::Int
    state::St
end
checkindex(c::FilterCheckpoint) = c.n

inputlength(x::DSP.Filters.Filter,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.Filter,n) = DSP.outputlength(x,n)
inputlength(x,n) = n
outputlength(x,n) = n
function checkpoints(x::FilteredSignal,offset,len,state=FilterState(x))
    map(@λ(FilterCheckpoint(_,state)),[1:x.blocksize:len; len+1] .+ offset)
end

struct NullBuffer
    len::Int
    ch::Int
end
Base.size(x::NullBuffer) = (x.len,x.ch)
Base.size(x::NullBuffer,n) = (x.len,x.ch)[n]
writesink!(x::NullBuffer,i,y) = y
Base.view(x::NullBuffer,i,j) = x

function beforecheckpoint(x::FilteredSignal,check,len)
    # refill buffer if necessary
    state = check.state
    if state.lastoutput == state.availableoutput
        # process any samples before offset that have yet to be processed
        if state.lastoffset < checkindex(check)-1
            len = checkindex(check) - state.lastoffset - 1
            sink!(NullBuffer(len,nchannels(x)),x,SignalTrait(x),
                checkpoints(x,0,len,state))
        end
        @assert state.lastoffset >= checkindex(check)-1

        # early samples may have left some output in the bufer,
        # only update the buffer if this is not true
        if state.lastoutput == state.availableoutput

            # write child samples to input buffer
            in_len = min(size(state.input,1),len)
            padded = pad(x.signal,zero)
            sink!(view(state.input,1:in_len,:),
                padded,SignalTrait(padded),state.lastoffset)

            # filter the input to the output buffer
            state.availableoutput = outputlength(state.h,in_len)
            for ch in 1:size(state.output,2)
                filt!(view(state.output,1:state.availableoutput,ch),
                    state.h,view(state.input,1:in_len,ch))
            end

            state.lastoutput = 0
        end
    end
end
function aftercheckpoint(x::FilteredSignal,check,len)
    check.state.lastoutput += len
    check.state.lastoffset += len
end

@Base.propagate_inbounds function sampleat!(result,x::FilteredSignal,
        sig,i,j,check)
    index = check.state.lastoutput+j-check.state.lastoffset
    writesink!(result,i,view(check.state.output,index,:))
end

# TODO: create an online version of normpower?
# TODO: this should be excuted lazzily to allow for unkonwn samplerates
struct NormedSignal{Si,T} <: WrappedSignal{Si,T}
    signal::Si
end
childsignal(x::NormedSignal) = x.signal
nsamples(x::NormedSignal) = nsamples(x.signal)
NormedSignal(x::Si) where Si = NormedSignal{Si,float(channel_eltype(Si))}(x)
SignalTrait(x::Type{T}) where {S,T <: NormedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:NormedSignal{<:Any,T}},::IsSignal{<:Any,Fs,L}) where {T,Fs,L} =
    IsSignal{T,Fs,L}()

struct NormedCheckpoint{R,V,C} <: AbstractCheckpoint
    rms::R
    vals::V
    child::C
    offset::Int
end
checkindex(x::NormedCheckpoint) = checkindex(x.child)

function checkpoints(x::NormedSignal,offset,len)
    siglen = len + offset
    vals = sink!(Array{channel_eltype(x)}(undef,siglen,nchannels(x)),
        x.signal,offset=0)

    rms = sqrt.(mean(float.(vals).^2,dims=1))
    map(checkpoints(x.signal,offset,len)) do check
        NormedCheckpoint(Tuple(rms),vals,check,offset)
    end
end
beforecheckpoint(x::NormedCheckpoint,check,len) = 
    beforecheckpoint(x.child,check.child,len)
aftercheckpoint(x::NormedCheckpoint,check,len) = 
    aftercheckpoint(x.child,check.child,len)
function tosamplerate(x::NormedSignal,s::IsSignal{<:Any,<:Number},
    ::ComputedSignal,fs;blocksize)

    NormedSignal(tosamplerate(x.signal,fs,blocksize=blocksize))
end
function tosamplerate(x::NormedSignal,::IsSignal{<:Any,Missing},
    __ignore__,fs;blocksize)

    NormedSignal(tosamplerate(x.signal,fs,blocksize=blocksize))
end

function sampleat!(result,x::NormedSignal,::IsSignal,i,j,check::NormedCheckpoint)
    writesink!(result,i,view(check.vals,j+check.offset,:) ./ check.rms)
end

"""
    normpower(x)

Divide all samples by the root-mean-squared value of the signal.
"""
function normpower(x) 
    x = signal(x)
    NormedSignal{typeof(x),float(channel_eltype(typeof(x)))}(signal(x))
end
# function normpower(x)
#     fs = samplerate(x)
#     x = sink(x)
#     x ./ sqrt.(mean(x.^2,dims=1)) |> signal(fs*Hz)
# end