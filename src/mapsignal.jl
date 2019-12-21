using Unitful
export mapsignal, mix, amplify, addchannel, channel

################################################################################
# binary operators

struct MapSignal{Fn,N,C,T,Fs,El,L,Si,Pd,PSi} <: AbstractSignal{T}
    fn::Fn
    val::El
    len::L
    signals::Si
    framerate::Fs
    padding::Pd
    padded_signals::PSi
    blocksize::Int
    bychannel::Bool
end

function MapSignal(fn::Fn,val::El,len::L,signals::Si,
    framerate::Fs,padding::Pd,blocksize::Int,bychannel::Bool) where
        {Fn,El,L,Si,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    N = El == NoValues ? 0 : length(signals)
    C = El == NoValues ? 1 : nchannels(signals[1])
    padded_signals = pad.(signals,Ref(padding))
    PSi = typeof(padded_signals)
    MapSignal{Fn,N,C,T,Fs,El,L,Si,Pd,PSi}(fn,val,len,signals,framerate,padding,
        padded_signals,blocksize,bychannel)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:MapSignal{<:Any,<:Any,<:Any,T,Fs,L}}) where {Fs,T,L} =
    IsSignal{T,Fs,L}()
nframes(x::MapSignal) = x.len
nchannels(x::MapSignal) = length(x.val)
framerate(x::MapSignal) = x.framerate
function duration(x::MapSignal)
    durs = duration.(x.signals) |> collect
    all(isinf,durs) ? inflen :
        any(ismissing,durs) ? missing :
        maximum(filter(!isinf,durs))
end
function toframerate(x::MapSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    if inHz(fs) < x.framerate
        # reframe input if we are downsampling
        mapsignal(cleanfn(x.fn),toframerate.(x.signals,fs,blocksize=blocksize)...,
            padding=x.padding,bychannel=x.bychannel,
            blocksize=x.blocksize)
    else
        # reframe output if we are upsampling
        toframerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

root(x::MapSignal) = reduce(mergeroot,root.(x.signals))

toframerate(x::MapSignal,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    mapsignal(cleanfn(x.fn),toframerate.(x.signals,fs,blocksize=blocksize)...,
        padding=x.padding,bychannel=x.bychannel,
        blocksize=x.blocksize)

"""
    mapsignal(fn,arguments...;padding,bychannel)

Apply `fn` across the frames of arguments, producing a signal of the output
of `fn`. Shorter signals are padded to accommodate the longest finite-length
signal. The function `fn` should treat each argument as a single number and
return a single number. This operation is broadcast across all channels of
the input. It is expected to be a type stable function.

Normally the signals are first promoted to have the same samle rate and the
same number of channels using [`uniform`](@ref) (with `channels=true`).

## Cross-channel functions

The function `fn` is normally broadcast across channels, but if you wish to
treat each channel separately you can set `bychannel=false`. In this case the
inputs to `fn` will be indexable objects (tuples or arrays) of all channel
values for a given frame, and `fn` should return a type-stable tuple value
(for a multi-channel or single-channel result) or a number (for a
single-channel result only). For example, the following would swap the left
and right channels.

```julia
x = rand(10,2)
swapped = mapsignal(x,bychannel=false) do val
    val[2],val[1]
end
```

When `bychannel=false` the channels of each signal are not promoted:

## Padding

Padding determines how frames past the end of shorter signals are reported.
The value of `padding` is passd to [`pad`](@ref). Its default value is
determined by the value of `fn`. The default value for the four basic
arithmetic operators is their identity (`one` for `*` and `zero` for `+`).
These defaults are set on the basis of `fn` using `default_pad(fn)`. A
fallback implementation of `default_pad` returns `zero`.

To define a new default for a specific function, just create a new method of
`default_pad(fn)`

```julia

myfun(x) = 2x + 3
SignalOperators.default_pad(::typeof(myfun)) = one

```

"""
function mapsignal(fn,xs...;padding = default_pad(fn),bychannel=true,
    blocksize=default_blocksize)

    xs = uniform(xs,channels=bychannel)
    fs = framerate(xs[1])
    lens = nframes.(xs) |> collect
    len = all(isinf,lens) ? inflen :
            any(ismissing,lens) ? missing :
            maximum(filter(!isinf,lens))

    vals = testvalue.(xs)
    if bychannel
        fn = FnBr(fn)
    end
    MapSignal(fn,astuple(fn(vals...)),len,xs,fs,padding,blocksize,
        bychannel)
end

struct FnBr{Fn}
    fn::Fn
end
(fn::FnBr)(xs...) = fn.fn.(xs...)
cleanfn(x) = x
cleanfn(x::FnBr) = x.fn

testvalue(x) = Tuple(zero(channel_eltype(x)) for _ in 1:nchannels(x))

const MAX_CHANNEL_STACK = 64

struct MapSignalBlock{Ch,C,O}
    len::Int
    offset::Int
    channels::Ch
    blocks::C
    offsets::O
end
nframes(x::MapSignalBlock) = x.len

function prepare_channels(x::MapSignal)
    nch = ntuple_N(typeof(x.val))
    (nch > MAX_CHANNEL_STACK && (x.fn isa FnBr)) ?
        Array{channel_eltype(x)}(undef,nch) :
        nothing
end

struct EmptyChildBlock
end
const emptychild = EmptyChildBlock()
nframes(::EmptyChildBlock) = 0
nextblock(x,maxlen,skip,::EmptyChildBlock) = nextblock(x,maxlen,skip)

initblock(x::MapSignal{<:Any,N}) where N =
    MapSignalBlock(0,0,prepare_channels(x),Tuple(emptychild for _ in 1:N),
        Tuple(zeros(N)))
function nextblock(x::MapSignal{Fn,N,CN},maxlen,skip,
    block::MapSignalBlock=initblock(x)) where {Fn,N,CN}

    maxlen = min(maxlen,nframes(x) - (block.offset + block.len))
    (maxlen == 0) && return nothing

    offsets = map(block.offsets, block.blocks) do offset, childblock
        offset += nframes(block)
        offset == nframes(childblock) ? 0 : offset
    end

    blocks = map(x.padded_signals,block.blocks,offsets) do sig, childblock, offset
        if offset == 0
            nextblock(sig,maxlen,skip,childblock)
        else
            childblock
        end
    end

    # find the smallest child block length, and use that as the length for the
    # parent block length
    len = min(maxlen,minimum(nframes.(blocks) .- offsets))
    Ch, C, O = typeof(block.channels), typeof(blocks), typeof(offsets)
    MapSignalBlock{Ch,C,O}(len,block.offset + block.len,block.channels,blocks,
        offsets)
end

trange(::Val{N}) where N = (trange(Val(N-1))...,N)
trange(::Val{1}) = (1,)

@Base.propagate_inbounds function frame(x::MapSignal{<:FnBr,N,CN},
    block::MapSignalBlock{<:Nothing},
    i::Int) where {N,CN}

    inputs = frame.(x.padded_signals,block.blocks,i .+ block.offsets)
    map(ch -> x.fn(map(@λ(_[ch]),inputs)...),trange(Val{CN}()))
end

@Base.propagate_inbounds function frame(
    x::MapSignal{<:FnBr,N,CN},
    block::MapSignalBlock{<:Array},
    i::Int) where {N,CN}

    inputs = frame.(x.padded_signals,block.blocks,i .+ block.offsets)
    map!(ch -> x.fn(map(@λ(_[ch]),inputs)...),block.channels,1:CN)
end

@Base.propagate_inbounds function frame(
    x::MapSignal{<:Any,N,CN},
    block::MapSignalBlock{<:Nothing},
    i::Int) where {N,CN}

    x.fn(frame.(x.padded_signals,block.blocks,i .+ block.offsets)...)
end

default_pad(x) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(/)) = one

Base.show(io::IO,::MIME"text/plain",x::MapSignal) = pprint(io,x)
function PrettyPrinting.tile(x::MapSignal)
    if length(x.signals) == 1
        tilepipe(signaltile(x.signals[1]),literal(string(mapstring(x.fn),")")))
    elseif length(x.signals) == 2
        operate =
            literal(mapstring(x.fn)) * signaltile(x.signals[2]) * literal(")") |
            literal(mapstring(x.fn)) / indent(4) * signaltile(x.signals[2]) /
                literal(")")
        tilepipe(signaltile(x.signals[1]),operate)
    else
        list_layout(signaltile.(collect(x.signals)),par=(mapstring(x.fn),")"))
    end
    # TODO: report the padding and bychannel values if a they are non-default
    # values
end
signaltile(x::MapSignal) = PrettyPrinting.tile(x)
mapstring(fn) = string("mapsignal(",fn,",")
mapstring(x::FnBr) = string("mapsignal(",x.fn,",")

"""

    mix(xs...)

Sum all signals together, using [`mapsignal`](@ref)

"""
mix(y) = x -> mix(x,y)
mix(xs...) = mapsignal(+,xs...)
mapstring(::FnBr{<:typeof(+)}) = "mix("

"""

    amplify(xs...)

Find the product, on a per-frame basis, for all signals `xs` using
[`mapsignal`](@ref).

"""
amplify(y) = x -> amplify(x,y)
amplify(xs...) = mapsignal(*,xs...)
mapstring(::FnBr{<:typeof(*)}) = "amplify("

"""

    addchannel(xs...)

Concatenate the channels of all signals into one signal, using
[`mapsignal`](@ref). This will result in a signal with `sum(nchannels,xs)`
channels.

"""
addchannel(y) = x -> addchannel(x,y)
addchannel(xs...) = mapsignal(tuplecat,xs...;bychannel=false)
tuplecat(a,b) = (a...,b...)
tuplecat(a,b,c,rest...) = reduce(tuplecat,(a,b,c,rest...))
mapstring(::typeof(tuplecat)) = "addchannel("

"""

    channel(x,n)

Select channel `n` of signal `x`, as a single-channel signal, using
[`mapsignal`](@ref).

"""
channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(GetChanFn(n),x,bychannel=false)
struct GetChanFn; n::Int; end
(fn::GetChanFn)(x) = x[fn.n]
mapstring(fn::GetChanFn) = string("channel(",fn.n)
