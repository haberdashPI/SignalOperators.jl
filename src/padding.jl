export cycle, mirror, lastsample

struct PaddedSignal{S,T} <: WrappedSignal{S,T}
    signal::S
    pad::T
end
SignalTrait(x::Type{T}) where {S,T <: PaddedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs}) where {T,Fs} =
    IsSignal{T,Fs,InfiniteLength}()
nsamples(x::PaddedSignal) = inflen
duration(x::PaddedSignal) = inflen
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    PaddedSignal(tosamplerate(x.signal,fs,blocksize=blocksize),x.pad)
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = PaddedSignal(tosamplerate(x.signal,fs;blocksize=blocksize),x.pad)

"""

    pad(x,padding)

Create a signal that appends an infinite number of values, `padding`, to `x`.
The value `padding` can be:

- a number
- a tuple or vector
- a type function: a one argument function of the `channel_eltype` of `x`
- a value function: a one argument function of the signal `x` for which
    `SignalOperators.valuefunction(padding) == true`.
- an indexing function: a three argument function following the same type
  signature as `getindex` for two dimensional arrays.

If the signal is already infinitely long (e.g. a previoulsy padded signal),
`pad` has no effect.

If `padding` is a number it is used as the value for all samples and channels
past the end of `x`.

If `padding` is a tuple or vector it is the value for all samples past the end
of `x`.

If `padding` is a type function it is passed the [`channel_eltype`](@ref) of
the signal and the resulting value is used as the value for all samples past
the end of `x`. Examples include `zero` and `one`

If `padding` is a value function it is passed `x` just before padding during
`sink` begins and it should return a tuple of `channel_eltype(x)` values.
This value is repeated for the remaining samples. It is generally only useful
when x is an AbstractArray.

If `padding` is an indexing function (it accepts 3 arguments) it will be used
to retrieve samples from the signal `x` assuming it conforms to the
`AbstractArray` interface, with the first index being samples and the second
channels. If the sample index goes past the bounds of the array, it should be
transformed to an index within the range of that array. Note that such
padding functions only work on signals that are also AbstractArray objects.
You can always generate an array from a given signal by first passing it
through `sink` or `sink!`.

## See also

[`cycle`](@ref)
[`mirror`](@ref)
[`lastsample`](@ref)
[`valuefunction`](@ref)
"""
pad(p) = x -> pad(x,p)
function pad(x,p)
    x = signal(x)
    isinf(nsamples(x)) ? x : PaddedSignal(x,p)
end

"""
    lastsample

When passed as an argument to `pad`, allows padding using the last sample of a
signal. You cannot use this function in other contexts, and it will normally
throw an error. See [`pad`](@ref).
"""
lastsample(x) = error("Must be passed as argument to `pad`.")

"""
    SignalOperators.valuefunction(fn)

Returns true if `fn` should be treated as a value function. See
[`pad`](@ref). If you wish your own function to be a value function, you can
do this as follows.

    SignalOperators.valuefunction(::typeof(myfun)) = true

"""
valuefunction(x) = false
valuefunction(::typeof(lastsample)) = true

"""
    cycle(x,i,j)

An indexing function which wraps index i using mod, thus
repeating the signal when i > size(x,1). It can be passed as the second
argument to [`pad`](@ref).
"""
@Base.propagate_inbounds cycle(x,i,j) = x[(i-1)%end+1,j]

"""
    mirror(x,i,j)

An indexing function which mirrors the indices when i > size(x,1). This means
that past the end of the signal x, the signal first repeats with samples in
reverse order, then repeats in the original order, so on and so forth. It
can be passed as the second argument to  [`pad`](@ref).
"""
@Base.propagate_inbounds function mirror(x,i,j)
    function helper(i,N)
       count,remainder = divrem(i-1,N)
       iseven(count) ? remainder+1 : N-remainder
    end
    x[helper(i,end),j]
end

usepad(x::PaddedSignal,block) = usepad(x,SignalTrait(x),block)
usepad(x::PaddedSignal,s::IsSignal,block) = usepad(x,s,x.pad,block)
usepad(x::PaddedSignal,s::IsSignal{T},p::Number,block) where T =
    Fill(convert(T,p),nchannels(x.signal))
function usepad(x::PaddedSignal,s::IsSignal{T},
    p::Union{Array,Tuple},block) where T

    map(x -> convert(T,x),p)
end
usepad(x::PaddedSignal,s::IsSignal,::typeof(lastsample),block) =
    sample(x,block,nsamples(block))
function usepad(x::PaddedSignal,s::IsSignal{T},fn::Function,block) where T
    nargs = map(x -> x.nargs - 1, methods(fn).ms)
    if 3 ∈ nargs
        if indexable(x.signal)
            i -> fn(x.signal,i,:)
        else
            io = IOBuffer()
            show(io,MIME("text/plain"),x)
            sig_string = String(take!(io))
            error("Attemped to specify an indexing pad function for the ",
                  "following signal, which is not known to support ",
                  "`getindex`.\n",sig_string)
        end
    elseif 1 ∈ nargs
        if valuefunction(fn)
            fn(x.signal)
        else
            Fill(fn(T),nchannels(x.signal))
        end
    else
        error("Pad function ($fn) must take 1 or 3 arguments. ",
              "Refering `pad` help.")
    end
end

child(x::PaddedSignal) = x.signal

struct UsePad
end
const use_pad = UsePad()

struct PadBlock{P,C}
    pad::P
    child_or_len::C
    offset::Int
end
child(x::PadBlock{<:Nothing}) = x.child_or_len
child(x::PadBlock) = nothing
nsamples(x::PadBlock{<:Nothing}) = nsamples(child(x))
nsamples(x::PadBlock) = x.child_or_len

@Base.propagate_inbounds sample(x,block::PadBlock{<:Nothing},i) =
    sample(child(x),child(block),i)
@Base.propagate_inbounds sample(x,block::PadBlock{<:Function},i) =
    block.pad(i + block.offset)
@Base.propagate_inbounds sample(x,block::PadBlock,i) = block.pad

function nextblock(x::PaddedSignal,maxlen,skip)
    block = nextblock(child(x),maxlen,skip)
    if isnothing(block)
        PadBlock(usepad(x,block),maxlen,0)
    else
        PadBlock(nothing,block,0)
    end
end

function nextblock(x::PaddedSignal,maxlen,skip,block::PadBlock{<:Nothing})
    childblock = nextblock(child(x),maxlen,skip,child(block))
    if isnothing(childblock)
        PadBlock(usepad(x,block),maxlen,nsamples(block) + block.offset)
    else
        PadBlock(nothing,childblock,nsamples(block) + block.offset)
    end
end
function nextblock(x::PaddedSignal,len,skip,block::PadBlock)
    PadBlock(block.pad,len,nsamples(block) + block.offset)
end

Base.show(io::IO,::MIME"text/plain",x::PaddedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::PaddedSignal)
    child = signaltile(x.signal)
    operate = literal(string("pad(",x.pad,")"))
    tilepipe(child,operate)
end
signaltile(x::PaddedSignal) = PrettyPrinting.tile(x)