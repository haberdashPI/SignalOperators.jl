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

function nyquist_check(x,hz)
    if !ismissing(framerate(x)) && inHz(hz) ≥ 0.5framerate(x)
        error("The frequency $(hz) cannot be represented at a sampling rate ",
              "of $(framerate(x)) Hz. Increase the sampling rate or lower ",
              "the frequency.")
    end
end

"""
    lowpass(x,low;[order=5],[method=Butterworth(order)],[blocksize])

Apply a lowpass filter to x at the given cutoff frequency (`low`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
lowpass(low;kwds...) = x->lowpass(x,low;kwds...)
function lowpass(x,low;order=5,method=Butterworth(order),
    blocksize=default_blocksize)

    nyquist_check(x,low)
    filtersignal(x, filterfn(Lowpass,method,low), blocksize=blocksize)
end

"""
    highpass(x,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a highpass filter to x at the given cutoff frequency (`low`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
highpass(high;kwds...) = x->highpass(x,high;kwds...)
function highpass(x,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize)

    nyquist_check(x,high)
    filtersignal(x, filterfn(Highpass,method,high),blocksize=blocksize)
end

"""
    bandpass(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandpass filter to x at the given cutoff frequencies (`low` and `high`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandpass(low,high;kwds...) = x->bandpass(x,low,high;kwds...)
function bandpass(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize)

    nyquist_check(x,low)
    nyquist_check(x,high)
    filtersignal(x, filterfn(Bandpass,method,low,high),blocksize=blocksize)
end

"""
    bandstop(x,low,high;[order=5],[method=Butterworth(order)],[blocksize])

Apply a bandstop filter to x at the given cutoff frequencies (`low` and `high`).
See [`filtersignal`](@ref) for details on `blocksize`.
"""
bandstop(low,high;kwds...) = x->bandstop(x,low,high;kwds...)
function bandstop(x,low,high;order=5,method=Butterworth(order),
    blocksize=default_blocksize)

    nyquist_check(x,low)
    nyquist_check(x,high)
    filtersignal(x, filterfn(Bandstop,method,low,high),blocksize=blocksize)
end

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
function filtersignal(x::Si,s::IsSignal,fn;blocksize,newfs=framerate(x)) where {Si}
    FilteredSignal(x,fn,blocksize,newfs)
end
struct FilteredSignal{T,Si,Fn,Fs} <: WrappedSignal{Si,T}
    signal::Si
    fn::Fn
    blocksize::Int
    framerate::Fs
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
framerate(x::FilteredSignal) = x.framerate
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

function toframerate(x::FilteredSignal,s::IsSignal{<:Any,<:Number},::ComputedSignal,fs;
blocksize)
    # is this a non-resampling filter?
    if framerate(x) == framerate(x.signal)
        FilteredSignal(toframerate(x.signal,fs,blocksize=blocksize),
            x.fn,x.blocksize,fs)
    else
        toframerate(x.signal,s,DataSignal(),fs,blocksize=blocksize)
    end
end
function toframerate(x::FilteredSignal,::IsSignal{<:Any,Missing},__ignore__,fs;
        blocksize)
    FilteredSignal(toframerate(x.signal,fs,blocksize=blocksize),
        x.fn,x.blocksize,fs)
end

function nframes(x::FilteredSignal)
    if ismissing(framerate(x.signal))
        missing
    elseif framerate(x) == framerate(x.signal)
        nframes(x.signal)
    else
        ceil(Int,nframes(x.signal)*framerate(x)/framerate(x.signal))
    end
end

struct FilterBlock{H,S,T,C}
    len::Int
    last_output_index::Int
    available_output::Int

    last_input_offset::Int
    last_output_offset::Int

    hs::Vector{H}
    input::Matrix{S}
    output::Matrix{T}

    child::C
end
child(x::FilterBlock) = x.child
init_length(x::FilteredSignal) = min(nframes(x),x.blocksize)
init_length(x::FilteredSignal{<:Any,<:Any,<:ResamplerFn}) =
    trunc(Int,min(nframes(x),x.blocksize) / x.fn.ratio)

struct UndefChild
end
const undef_child = UndefChild()
function FilterBlock(x::FilteredSignal)
    hs = [resolve_filter(x.fn(framerate(x))) for _ in 1:nchannels(x.signal)]
    len = init_length(x)
    input = Array{channel_eltype(x.signal)}(undef,len,nchannels(x))
    output = Array{channel_eltype(x)}(undef,x.blocksize,nchannels(x))

    FilterBlock(0,0,0, 0,0, hs,input,output,undef_child)
end
nframes(x::FilterBlock) = x.len
@Base.propagate_inbounds frame(::FilteredSignal,x::FilterBlock,i) =
    view(x.output,i+x.last_output_index,:)

inputlength(x,n) = n
outputlength(x,n) = n
inputlength(x::DSP.Filters.Filter,n) = DSP.inputlength(x,n)
outputlength(x::DSP.Filters.Filter,n) = DSP.outputlength(x,n)

function nextblock(x::FilteredSignal,maxlen,skip,
    block::FilterBlock=FilterBlock(x))

    last_output_index = block.last_output_index + block.len
    if nframes(x) == last_output_index
        return nothing
    end

    # check for leftover frames in the output buffer
    if last_output_index < block.available_output
        len = min(maxlen, block.available_output - last_output_index)

        FilterBlock(len, last_output_index, block.available_output,
            block.last_input_offset, block.last_output_offset, block.hs,
            block.input, block.output, block.child)
    # otherwise, generate more filtered output
    else
        @assert !isnothing(child(block))

        psig = pad(x.signal,zero)
        childblock = !isa(child(block), UndefChild) ?
            nextblock(psig,size(block.input,1),false,child(block)) :
            nextblock(psig,size(block.input,1),false)
        childblock = sink!(block.input,psig,SignalTrait(psig),childblock)
        last_input_offset = block.last_input_offset + size(block.input,1)

        # filter the input into the output buffer
        out_len = outputlength(block.hs[1],size(block.input,1))
        for ch in 1:size(block.output,2)
            filt!(view(block.output,1:out_len,ch),block.hs[ch],
                    view(block.input,:,ch))
        end
        last_output_offset = block.last_output_offset + out_len

        FilterBlock(min(maxlen,out_len), 0,
            out_len, last_input_offset, last_output_offset, block.hs,
            block.input, block.output, childblock)
    end
end

# TODO: create an online version of normpower?
# TODO: this should be excuted lazzily to allow for unkonwn framerates
struct NormedSignal{Si,T} <: WrappedSignal{Si,T}
    signal::Si
end
child(x::NormedSignal) = x.signal
nframes(x::NormedSignal) = nframes(x.signal)
NormedSignal(x::Si) where Si = NormedSignal{Si,float(channel_eltype(Si))}(x)
SignalTrait(x::Type{T}) where {S,T <: NormedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:NormedSignal{<:Any,T}},::IsSignal{<:Any,Fs,L}) where {T,Fs,L} =
    IsSignal{T,Fs,L}()
function toframerate(x::NormedSignal,s::IsSignal{<:Any,<:Number},
    ::ComputedSignal,fs;blocksize)

    NormedSignal(toframerate(x.signal,fs,blocksize=blocksize))
end
function toframerate(x::NormedSignal,::IsSignal{<:Any,Missing},
    __ignore__,fs;blocksize)

    NormedSignal(toframerate(x.signal,fs,blocksize=blocksize))
end

struct NormedBlock{A}
    offset::Int
    len::Int
    vals::A
end
nframes(x::NormedBlock) = x.len
@Base.propagate_inbounds frame(::NormedSignal,x::NormedBlock,i) =
    view(x.vals,i,:)

function initblock(x::NormedSignal)
    if isinf(nframes(x))
        error("Cannot normalize an infinite-length signal. Please ",
              "use `until` to take a prefix of the signal")
    end
    vals = Array{channel_eltype(x)}(undef,nframes(x),nchannels(x))
    sink!(vals, x.signal)

    rms = sqrt(mean(x -> float(x)^2,vals))
    vals ./= rms

    S,V = typeof(x), typeof(vals)
    NormedBlock(0,0,vals)
end

function nextblock(x::NormedSignal,maxlen,skip,block::NormedBlock=initblock(x))
    len = min(maxlen,nframes(x) - block.offset)
    NormedBlock(block.offset + block.len, len, block.vals)
end

"""
    normpower(x)

Return a signal with normalized power. That is, divide all frames by the
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