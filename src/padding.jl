export Pad, cycle, mirror, lastframe, unextended_nframes

"""

    unextended_nframes(x)

Normally equal to `nframes(x)`. However, a few signals override this method
to make it a different value, for use with `OperateOn` (e.g. numbers and
extended signals).

## See Also

[`OperateOn`](@ref)
[`Extend`](@ref)
[`Signal`](@ref)

"""

struct PaddedSignal{S,T,E} <: WrappedSignal{S,T}
    signal::S
    Pad::T
end
PaddedSignal(x::S,pad::T,extending=false) where {S,T} =
    PaddedSignal{S,T,extending}(x,pad)
SignalTrait(x::Type{T}) where {S,T <: PaddedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs}) where {T,Fs} =
    IsSignal{T,Fs,InfiniteLength}()
nframes_helper(x::PaddedSignal) = inflen
duration(x::PaddedSignal) = inflen
ToFramerate(x::PaddedSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    PaddedSignal(ToFramerate(x.signal,fs,blocksize=blocksize),x.Pad)
ToFramerate(x::PaddedSignal,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = PaddedSignal(ToFramerate(x.signal,fs;blocksize=blocksize),x.Pad)

"""

    Pad(x,padding)

Create a signal that appends an infinite number of values, `padding`, to `x`.
The value `padding` can be:

- a number
- a tuple or vector
- a type function: a one argument function of the `sampletype` of `x`
- a value function: a one argument function of the signal `x` for which
    `SignalOperators.valuefunction(padding) == true`.
- an indexing function: a three argument function following the same type
  signature as `getindex` for two dimensional arrays.

If the signal is already infinitely long (e.g. a previoulsy padded signal),
`Pad` has no effect.

If `padding` is a number it is used as the value for all samples past the end
of `x`.

If `padding` is a tuple or vector it is the value for all frames past the end
of `x`.

If `padding` is a type function it is passed the [`sampletype`](@ref) of
the signal and the resulting value is used as the value for all frames past
the end of `x`. Examples include `zero` and `one`

If `padding` is a value function it is passed the signal `x` just before
padding occurs during a call to `sink`; it should return a tuple of
`sampletype(x)` values. The return value is repeated for all remaining
frames of the signal. For example, [`lastframe`](@ref) is a value function.

If `padding` is an indexing function (it accepts 3 arguments) it will be used
to retrieve frames from the signal `x` assuming it conforms to the
`AbstractArray` interface, with the first index being frames and the second
channels. If the frame index goes past the bounds of the array, it should be
transformed to an index within the range of that array. Note that such
padding functions only work on signals that are also AbstractArray objects.
You can always generate an array from a given signal by first passing it
through `sink` or `sink!`.

!!! info

    A indexing function will also work on a signal represented as a tuple of
    an array and number; it simply passed the array (leaving off the number).

## See also

[`cycle`](@ref)
[`mirror`](@ref)
[`lastframe`](@ref)
[`valuefunction`](@ref)
"""
Pad(p) = x -> Pad(x,p)
function Pad(x,p)
    x = Signal(x)
    isknowninf(nframes(x)) ? x : PaddedSignal(x,p)
end


"""

    Extend(x,padding)

Behaves like [`Pad`](@ref), except when passed directly to
[`OperateOn`](@ref), the signal `x` will only be padded up to the length of
the longest input signal.

## See Also

[`OperateOn`](@ref)
[`Pad`](@ref)

"""
Extend(p) = x -> Extend(x,p)
function Extend(x,p)
    x = Signal(x)
    isknowninf(nframes(x)) ? x : PaddedSignal(x,p,true)
end

"""
    lastframe

When passed as an argument to `Pad`, allows padding using the last frame of a
signal. You cannot use this function in other contexts, and it will normally
throw an error. See [`Pad`](@ref).
"""
lastframe(x) = error("Must be passed as argument to `Pad`.")

"""
    SignalOperators.valuefunction(fn)

Returns true if `fn` should be treated as a value function. See
[`Pad`](@ref). If you wish your own function to be a value function, you can
do this as follows.

    SignalOperators.valuefunction(::typeof(myfun)) = true

"""
valuefunction(x) = false
valuefunction(::typeof(lastframe)) = true

"""
    cycle(x,i,j)

An indexing function which wraps index i using mod, thus
repeating the signal when i > size(x,1). It can be passed as the second
argument to [`Pad`](@ref).
"""
@Base.propagate_inbounds cycle(x,i,j) = x[(i-1)%end+1,j]

"""
    mirror(x,i,j)

An indexing function which mirrors the indices when i > size(x,1). This means
that past the end of the signal x, the signal first repeats with frames in
reverse order, then repeats in the original order, so on and so forth. It
can be passed as the second argument to  [`Pad`](@ref).
"""
@Base.propagate_inbounds function mirror(x,i,j)
    function helper(i,N)
       count,remainder = divrem(i-1,N)
       iseven(count) ? remainder+1 : N-remainder
    end
    x[helper(i,end),j]
end

usepad(x::PaddedSignal,block) = usepad(x,SignalTrait(x),block)
usepad(x::PaddedSignal,s::IsSignal,block) = usepad(x,s,x.Pad,block)
usepad(x::PaddedSignal,s::IsSignal{T},p::Number,block) where T =
    Fill(convert(T,p),nchannels(x.signal))
function usepad(x::PaddedSignal,s::IsSignal{T},
    p::Union{Array,Tuple},block) where T

    map(x -> convert(T,x),p)
end
usepad(x::PaddedSignal,s::IsSignal,::typeof(lastframe),block) =
    frame(x,block,nframes(block))
usepad(x::PaddedSignal,s::IsSignal,::typeof(lastframe),::Nothing) =
    error("Signal is length zero; there is no last frame to pad with.")

indexable(x::AbstractArray) = true
indexable(x::Tuple{<:AbstractArray,<:Number}) = true
indexable(x) = false
indexing(x::AbstractArray) = x
indexing(x::Tuple{<:AbstractArray,<:Number}) = x[1]
function usepad(x::PaddedSignal,s::IsSignal{T},fn::Function,block) where T
    nargs = map(x -> x.nargs - 1, methods(fn).ms)
    if 3 ∈ nargs
        if indexable(x.signal)
            i -> fn(indexing(x.signal),i,:)
        else
            io = IOBuffer()
            show(io,MIME("text/plain"),child(x))
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
              "Refer to `Pad` documentation.")
    end
end

child(x::PaddedSignal) = x.signal

struct UsePad
end
const use_pad = UsePad()

struct PadBlock{P,C}
    Pad::P
    child_or_len::C
    offset::Int
end
child(x::PadBlock{<:Nothing}) = x.child_or_len
child(x::PadBlock) = nothing
nframes(x::PadBlock{<:Nothing}) = nframes(child(x))
nframes(x::PadBlock) = x.child_or_len

@Base.propagate_inbounds frame(x,block::PadBlock{<:Nothing},i) =
    frame(child(x),child(block),i)
@Base.propagate_inbounds frame(x,block::PadBlock{<:Function},i) =
    block.Pad(i + block.offset)
@Base.propagate_inbounds frame(x,block::PadBlock,i) = block.Pad

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
        PadBlock(usepad(x,block),maxlen,nframes(block) + block.offset)
    else
        PadBlock(nothing,childblock,nframes(block) + block.offset)
    end
end
function nextblock(x::PaddedSignal,len,skip,block::PadBlock)
    PadBlock(block.Pad,len,nframes(block) + block.offset)
end

Base.show(io::IO,::MIME"text/plain",x::PaddedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::PaddedSignal)
    child = signaltile(x.signal)
    operate = literal(string("Pad(",x.Pad,")"))
    tilepipe(child,operate)
end
function PrettyPrinting.tile(x::PaddedSignal{<:Any,<:Any,true})
    child = signaltile(x.signal)
    operate = literal(string("Extend(",x.Pad,")"))
    tilepipe(child,operate)
end
signaltile(x::PaddedSignal) = PrettyPrinting.tile(x)