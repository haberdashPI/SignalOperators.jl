export lowpass, highpass, bandpass, bandstop, normpower, filtersignal

const default_blocksize = 2^12

struct FilterFn{D,M,A}
    design::D
    method::M
    args::A
end
(fn::FilterFn)(fs) =
    digitalfilter(fn.design(inHz.(fn.args)...,fs=inHz(fs)),fn.method)
filterfn(design,method,args...) = FilterFn(design,method,args)

"""
    lowpass(x,low;[order=5],[method=Butterworth(order)],[blocksize])

Apply a lowpass filter to x at the given cutoff frequency (`low`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
lowpass(x,low;order=5,method=Butterworth(order),blocksize=default_blocksize) =
    filtersignal(x, filterfn(Lowpass,method,low), blocksize=blocksize)

"""
    highpass(x,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a highpass filter to x at the given cutoff frequency (`low`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
highpass(high;kwds...) = x->highpass(x,high;kwds...)
highpass(x,high;order=5,method=Butterworth(order),blocksize=default_blocksize) =
    filtersignal(x, filterfn(Highpass,method,high),blocksize=blocksize)

"""
    bandpass(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandpass filter to x at the given cutoff frequencies (`low` and `high`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
bandpass(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) =
    filtersignal(x, filterfn(Bandpass,method,low,high),blocksize=blocksize)

"""
    bandstop(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandstop filter to x at the given cutoff frequencies (`low` and `high`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
bandstop(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize) =
    filtersignal(x, filterfn(Bandstop,method,low,high),blocksize=blocksize)

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
filtersignal(x,fn::Union{FilterFn,Function};kwds...) =
    filtersignal(x,SignalTrait(x),fn;kwds...)
filtersignal(x,h;kwds...) =
    filtersignal(x,SignalTrait(x),RawFilterFn(h);kwds...)
function filtersignal(x,::Nothing,args...;kwds...)
    filtersignal(signal(x),args...;kwds...)
end

struct RawFilterFn{H}
    h::H
end
(fn::RawFilterFn)(fs) = deepcopy(fn.h)

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
child(x::FilteredSignal) = x.signal
samplerate(x::FilteredSignal) = x.samplerate
EvalTrait(x::FilteredSignal) = ComputedSignal()

Base.show(io::IO,::MIME"text/plain",x::FilteredSignal) = pprint(io,x)
function PrettyPrinting.tile(x::FilteredSignal)
    child = signaltile(x.signal)
    operate = literal(filterstring(x.fn))
    tilepipe(child,operate)
end
signaltile(x::FilteredSignal) = PrettyPrinting.tile(x)
filterstring(fn::FilterFn) =
    string(filterstring(fn.design),"(",join(string.(fn.args),","),")")
filterstring(fn::Function) = string("filtersignal(",string(fn),")")
function filtertring(fn::RawFilterFn)
    io = IOBuffer()
    show(IOContext(io,:displaysize=>(1,30),:limit=>true),
        MIME("text/plain"),x)
    string("filtersignal(",String(take!(io)),")")
end
filterstring(::Type{<:Lowpass}) = "lowpass"
filterstring(::Type{<:Highpass}) = "highpass"
filterstring(::Type{<:Bandpass}) = "bandpass"
filterstring(::Type{<:Bandstop}) = "bandstop"
filterstring(x) = string(x)

mutable struct FilterState{H,Fs,S,T}
    hs::Vector{H}
    samplerate::Fs
    last_input_offset::Int
    first_output_offset::Int
    last_output_offset::Int
    lastoutput::Int

    input::Matrix{S}
    output::Matrix{T}
    function FilterState(hs::Vector{H},fs::Fs,last_input_offset::Int,
        first_output_offset::Int,last_output_offset::Int,lastoutput::Int,
        input::Matrix{S},
        output::Matrix{T}) where {H,Fs,S,T}

        new{H,Fs,S,T}(hs,fs,last_input_offset,first_output_offset,
            last_output_offset,lastoutput,input,output)
    end
end
init_length(x::FilteredSignal) = x.blocksize
init_length(x::FilteredSignal{<:Any,<:Any,<:ResamplerFn}) =
    trunc(Int,x.blocksize / x.fn.ratio)
function FilterState(x::FilteredSignal)
    hs = [resolve_filter(x.fn(samplerate(x))) for _ in 1:nchannels(x.signal)]
    len = init_length(x)
    input = Array{channel_eltype(x.signal)}(undef,len,nchannels(x))
    output = Array{channel_eltype(x)}(undef,x.blocksize,nchannels(x))
    last_input_offset = 0
    first_output_offset = 0
    last_output_offset = 0
    lastoutput = 0

    FilterState(hs,float(samplerate(x)),last_input_offset,first_output_offset,
        last_output_offset,lastoutput,input,output)
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

struct FilterCheckpoint{S,St} <: AbstractCheckpoint{S}
    n::Int
    state::St
end
checkindex(c::FilterCheckpoint) = c.n

struct NullBuffer
    len::Int
    ch::Int
end
Base.size(x::NullBuffer) = (x.len,x.ch)
Base.size(x::NullBuffer,n) = (x.len,x.ch)[n]
writesink!(x::NullBuffer,i,y) = y
Base.view(x::NullBuffer,i,j) = x

inputlength(x,n) = n
outputlength(x,n) = n
inputlength(x::DSP.Filters.Filter,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.Filter,n) = DSP.outputlength(x,n)

function atcheckpoint(x::FilteredSignal,offset::Number,stopat,state=FilterState(x))
    S,St  = typeof(x), typeof(state)
    FilterCheckpoint{S,St}(max(state.last_output_offset+1,offset+1),state)
end

function atcheckpoint(x::S,check::AbstractCheckpoint{S},stopat) where
    S <: FilteredSignal

    state = prepare_state!(x,check.state,checkindex(check))
    # if there's output to produce, create a new checkpoint
    if min(state.last_output_offset,stopat) > checkindex(check)
        St  = typeof(state)
        FilterCheckpoint{S,St}(min(state.last_output_offset+1,stopat+1),state)

    # otherwise, indicate that there is no more data
    else
        nothing
    end
end

function prepare_state!(x,state,index)
    if state.last_output_offset+1 ≤ index
        # drop any samples that we do not wish to generate output for
        if state.last_output_offset+1 < index
            recurse_len = index - (state.last_output_offset + 1)
            sink!(NullBuffer(recurse_len,nchannels(x)),x,SignalTrait(x),
                  0,atcheckpoint(x,0,recurse_len,state))
        end
        @assert state.last_output_offset+1 ≥ index

        if state.last_output_offset+1 == index
            state.first_output_offset = state.last_output_offset
            # write child samples to input buffer
            # @show x.blocksize
            # @show nsamples(x)-state.last_input_offset

            psig = pad(x.signal,zero)
            sink!(state.input,psig,SignalTrait(psig),
                state.last_input_offset)
            state.last_input_offset += size(state.input,1)

            # filter the input to the output buffer
            out_len = outputlength(state.hs[1],size(state.input,1))
            for ch in 1:size(state.output,2)
                filt!(view(state.output,1:out_len,ch),state.hs[ch],
                        view(state.input,:,ch))
            end
            state.last_output_offset += out_len
        end
    end
    @assert state.last_output_offset ≥ index ||
        state.last_output_offset == nsamples(x)

    state
end

@Base.propagate_inbounds function sampleat!(result,x::FilteredSignal,i,j,check)
    index = j-check.state.first_output_offset
    writesink!(result,i,view(check.state.output,index,:))
end

# TODO: create an online version of normpower?
# TODO: this should be excuted lazzily to allow for unkonwn samplerates
struct NormedSignal{Si,T} <: WrappedSignal{Si,T}
    signal::Si
end
child(x::NormedSignal) = x.signal
nsamples(x::NormedSignal) = nsamples(x.signal)
NormedSignal(x::Si) where Si = NormedSignal{Si,float(channel_eltype(Si))}(x)
SignalTrait(x::Type{T}) where {S,T <: NormedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:NormedSignal{<:Any,T}},::IsSignal{<:Any,Fs,L}) where {T,Fs,L} =
    IsSignal{T,Fs,L}()
function tosamplerate(x::NormedSignal,s::IsSignal{<:Any,<:Number},
    ::ComputedSignal,fs;blocksize)

    NormedSignal(tosamplerate(x.signal,fs,blocksize=blocksize))
end
function tosamplerate(x::NormedSignal,::IsSignal{<:Any,Missing},
    __ignore__,fs;blocksize)

    NormedSignal(tosamplerate(x.signal,fs,blocksize=blocksize))
end

struct NormedCheckpoint{S,V} <: AbstractCheckpoint{S}
    n::Int
    vals::V
end
checkindex(x::NormedCheckpoint) = x.n

function atcheckpoint(x::NormedSignal,offset::Number,stopat)
    if isinf(nsamples(x))
        error("Cannot normalize an infinite-length signal. Please ",
              "use `until` to take a prefix of the signal")
    end
    vals = sink!(Array{channel_eltype(x)}(undef,nsamples(x),nchannels(x)),
        x.signal,offset=0)

    rms = sqrt(mean(x -> float(x)^2,vals))
    vals ./= rms

    S,V = typeof(x), typeof(vals)
    NormedCheckpoint{typeof(x),typeof(vals)}(offset+1,vals)
end

function atcheckpoint(x::S,check::AbstractCheckpoint{S},stopat) where
    S <: NormedSignal

    checkindex(check) == stopat ? nothing :
        NormedCheckpoint{typeof(x),typeof(check.vals)}(stopat+1,check.vals)
end

@Base.propagate_inbounds function sampleat!(result,x::NormedSignal,
    i,j,check::NormedCheckpoint)

    writesink!(result,i,view(check.vals,j,:))
end

"""
    normpower(x)

Return a signal with normalized power. That is, divide all samples by the
root-mean-squared value of the entire signal.

"""
function normpower(x)
    x = signal(x)
    NormedSignal{typeof(x),float(channel_eltype(typeof(x)))}(signal(x))
end

Base.show(io::IO,::MIME"text/plain",x::NormedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::NormedSignal)
    tilepipe(signaltile(x.signal),literal("normpower"))
end
signaltile(x::NormedSignal) = PrettyPrinting.tile(x)