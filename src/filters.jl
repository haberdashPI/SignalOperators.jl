export Normpower, Filt, normpower, filt, Lowpass, Bandpass, Bandstop, Highpass

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
              "of $(framerate(x)) Hz. Increase the frame rate or lower ",
              "the frequency.")
    end
end

"""

    Filt(x,::Type{<:FilterType},bounds...;method=Butterworth(order),order=5,
         blocksize=4096)

Apply the given filter type (e.g. `Lowpass`) using the given method to design
the filter coefficients. The type is specified as per the types from
[`DSP`](https://github.com/JuliaDSP/DSP.jl)

    Filt(x,h;[blocksize=4096])

Apply the given digital filter `h` (from
[`DSP`](https://github.com/JuliaDSP/DSP.jl)) to signal `x`.

## Blocksize

Blocksize determines the size of the buffer used when computing intermediate
values of the filter. It need not normally be adjusted, though changing it
can alter how efficient filter application is.

!!! note

    The non-lazy version of `Filt` is `filt` from the
    [`DSP`](https://github.com/JuliaDSP/DSP.jl) package. Proper methods have
    been defined such that it should be possible to call `filt` on a signal
    and get a signal back.

    The argument order for `filt` follows a different convention, with `x`
    coming after the filter specification. In contrast, `Filt` uses the
    convention of keeping `x` as the first argument to make piping possible.

"""
Filt(::Type{T},bounds...;kwds...) where T <: DSP.Filters.FilterType =
    x -> Filt(x,T,bounds...;kwds...)
function Filt(x,::Type{F},bounds...;blocksize=default_blocksize,order=5,
    method=Butterworth(order)) where F <: DSP.Filters.FilterType

    nyquist_check.(Ref(x),bounds)
    Filt(x, filterfn(F,method,bounds...),blocksize=blocksize)
end

Filt(h;kwds...) = x -> Filt(x,h;kwds...)
Filt(x,fn::Union{FilterFn,Function};kwds...) = Filt(x,SignalTrait(x),fn;kwds...)
Filt(x,h;kwds...) = Filt(x,SignalTrait(x),RawFilterFn(h);kwds...)
Filt(x,::Nothing,args...;kwds...) = Filt(Signal(x),args...;kwds...)

function DSP.filt(
    b::Union{AbstractVector, Number}, a::Union{AbstractVector, Number},
    x::AbstractSignal,
    si::AbstractArray{S} = DSP._zerosi(b,a,T)) where {T,S}

    R = promote_type(eltype(b), eltype(a), T, S)
    data = initsink(ToEltype(x,R),refineroot(root(x)))
    filt!(data,b,a,sink(x,Array),si)

    data
end

function DSP.filt!(
    data::AbstractArray,
    b::Union{AbstractVector, Number}, a::Union{AbstractVector, Number},
    x::AbstractSignal,
    si::AbstractArray{S} = DSP._zerosi(b,a,T)) where {T,S}

    filt!(data,b,a,sink(x,Array),si)
end

struct RawFilterFn{H}
    h::H
end
(fn::RawFilterFn)(fs) = deepcopy(fn.h)

resolve_filter(x) = DSP.Filters.DF2TFilter(x)
resolve_filter(x::FIRFilter) = x
Filt(x,s::IsSignal,fn;blocksize=default_blocksize,newfs=framerate(x)) =
    FilteredSignal(x,fn,blocksize,newfs)
struct FilteredSignal{T,Si,Fn,Fs} <: WrappedSignal{Si,T}
    signal::Si
    fn::Fn
    blocksize::Int
    framerate::Fs
end
function FilteredSignal(signal::Si,fn::Fn,blocksize::Number,newfs::Fs) where {Si,Fn,Fs}
    T = float(sampletype(signal))
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
function filterstring(fn::FilterFn)
    if isempty(fn.args)
        string("Filt(",designstring(fn.design),")")
    else
        string("Filt(",designstring(fn.design),",",
            join(string.(fn.args),","),")")
    end
end
filterstring(x) = string("Filt(",string(x),")")
function filtertring(fn::RawFilterFn)
    io = IOBuffer()
    show(IOContext(io,:displaysize=>(1,30),:limit=>true),
        MIME("text/plain"),x)
    string("Filt(",String(take!(io)),")")
end
designstring(::Type{<:Lowpass}) = "Lowpass"
designstring(::Type{<:Highpass}) = "Highpass"
designstring(::Type{<:Bandpass}) = "Bandpass"
designstring(::Type{<:Bandstop}) = "Bandstop"

function ToFramerate(x::FilteredSignal,s::IsSignal{<:Any,<:Number},::ComputedSignal,fs;
blocksize)
    # is this a non-resampling filter?
    if framerate(x) == framerate(x.signal)
        FilteredSignal(ToFramerate(x.signal,fs,blocksize=blocksize),
            x.fn,x.blocksize,fs)
    else
        ToFramerate(x.signal,s,DataSignal(),fs,blocksize=blocksize)
    end
end
function ToFramerate(x::FilteredSignal,::IsSignal{<:Any,Missing},__ignore__,fs;
        blocksize)
    FilteredSignal(ToFramerate(x.signal,fs,blocksize=blocksize),
        x.fn,x.blocksize,fs)
end

function nframes_helper(x::FilteredSignal)
    if ismissing(framerate(x.signal))
        missing
    elseif framerate(x) == framerate(x.signal)
        nframes_helper(x.signal)
    else
        ceil(Int,nframes_helper(x.signal)*framerate(x)/framerate(x.signal))
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
init_length_(x) =
    ismissing(nframes(x)) ? x.blocksize : min(nframes(x),x.blocksize)
init_length(x::FilteredSignal,h) = init_length_(x)
function init_length(x::FilteredSignal{<:Any,<:Any,<:ResamplerFn},h)
    n = trunc(Int,max(1,init_length_(x) / x.fn.ratio))
    out = DSP.outputlength(h,n)
    if out > 0
        n
    else
        n = trunc(Int,max(1,x.blocksize / x.fn.ratio))
        out = DSP.outputlength(h,n)
        if out > 0
            n
        else
            error("Blocksize is too small for this resampling filter.")
        end
    end
end

struct UndefChild
end
const undef_child = UndefChild()
function FilterBlock(x::FilteredSignal)
    hs = [resolve_filter(x.fn(framerate(x))) for _ in 1:nchannels(x.signal)]
    len = init_length(x,hs[1])
    input = Array{sampletype(x.signal)}(undef,len,nchannels(x))
    output = Array{sampletype(x)}(undef,x.blocksize,nchannels(x))

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
    # TODO: figure out how to end the filtering when we don't know the length
    # of the input signal (we need to compute its length and use that)
    if nframes_helper(x) == last_output_index
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

        psig = Pad(x.signal,zero)
        childblock = !isa(child(block), UndefChild) ?
            nextblock(psig,size(block.input,1),false,child(block)) :
            nextblock(psig,size(block.input,1),false)
        childblock = sink!(block.input,psig,SignalTrait(psig),childblock)
        last_input_offset = block.last_input_offset + size(block.input,1)

        # filter the input into the output buffer
        out_len = outputlength(block.hs[1],size(block.input,1))
        if out_len ≤ 0
            error("Unexpected non-positive output length!")
        end
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

# TODO: create an online version of Normpower?
# TODO: this should be excuted lazzily to allow for unkonwn framerates
struct NormedSignal{Si,T} <: WrappedSignal{Si,T}
    signal::Si
end
child(x::NormedSignal) = x.signal
nframes_helper(x::NormedSignal) = nframes_helper(x.signal)
NormedSignal(x::Si) where Si = NormedSignal{Si,float(sampletype(x))}(x)
SignalTrait(x::Type{T}) where {S,T <: NormedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:NormedSignal{<:Any,T}},::IsSignal{<:Any,Fs,L}) where {T,Fs,L} =
    IsSignal{T,Fs,L}()
function ToFramerate(x::NormedSignal,s::IsSignal{<:Any,<:Number},
    ::ComputedSignal,fs;blocksize)

    NormedSignal(ToFramerate(x.signal,fs,blocksize=blocksize))
end
function ToFramerate(x::NormedSignal,::IsSignal{<:Any,Missing},
    __ignore__,fs;blocksize)

    NormedSignal(ToFramerate(x.signal,fs,blocksize=blocksize))
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
    if isknowninf(nframes(x))
        error("Cannot normalize an infinite-length signal. Please ",
              "use `Until` to take a prefix of the signal")
    end
    vals = Array{sampletype(x)}(undef,nframes(x),nchannels(x))
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
    Normpower(x)

Return a signal with normalized power. That is, divide all frames by the
root-mean-squared value of the entire signal.

"""
function Normpower(x)
    x = Signal(x)
    NormedSignal{typeof(x),float(sampletype(x))}(Signal(x))
end


"""
    normpower(x)

Equivalent to `sink(Normpower(x))`

## See also

[`Normpower`](@ref)

"""
normpower(x) = sink(Normpower(x))

Base.show(io::IO,::MIME"text/plain",x::NormedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::NormedSignal)
    tilepipe(signaltile(x.signal),literal("Normpower"))
end
signaltile(x::NormedSignal) = PrettyPrinting.tile(x)