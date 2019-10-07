using Unitful
export mapsignal, mix, amplify, addchannel, channel

################################################################################
# binary operators

struct MapSignal{Fn,N,C,T,Fs,El,L,Si,Pd,PSi} <: AbstractSignal{T}
    fn::Fn
    val::El
    len::L
    signals::Si
    samplerate::Fs
    padding::Pd
    padded_signals::PSi
    blocksize::Int
    bychannel::Bool
end

function MapSignal(fn::Fn,val::El,len::L,signals::Si,
    samplerate::Fs,padding::Pd,blocksize::Int,bychannel::Bool) where 
        {Fn,El,L,Si,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    N = El == NoValues ? 0 : length(signals)
    C = El == NoValues ? 1 : nchannels(signals[1])
    padded_signals = pad.(signals,Ref(padding))
    PSi = typeof(padded_signals)
    MapSignal{Fn,N,C,T,Fs,El,L,Si,Pd,PSi}(fn,val,len,signals,samplerate,padding,
        padded_signals,blocksize,bychannel)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:MapSignal{<:Any,<:Any,<:Any,T,Fs,L}}) where {Fs,T,L} = 
    IsSignal{T,Fs,L}()
nsamples(x::MapSignal) = x.len
nchannels(x::MapSignal) = length(x.val)
samplerate(x::MapSignal) = x.samplerate
function duration(x::MapSignal)
    durs = duration.(x.signals) |> collect
    all(isinf,durs) ? inflen :
        any(ismissing,durs) ? missing :
        maximum(filter(!isinf,durs))
end
function tosamplerate(x::MapSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    if inHz(fs) < x.samplerate
        # resample input if we are downsampling 
        mapsignal(cleanfn(x.fn),tosamplerate.(x.signals,fs,blocksize=blocksize)...,
            padding=x.padding,bychannel=x.bychannel,
            blocksize=x.blocksize)
    else
        # resample output if we are upsampling
        tosamplerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

tosamplerate(x::MapSignal,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    mapsignal(cleanfn(x.fn),tosamplerate.(x.signals,fs,blocksize=blocksize)...,
        padding=x.padding,bychannel=x.bychannel,
        blocksize=x.blocksize)

"""
    mapsignal(fn,arguments...;padding,bychannel)

Apply `fn` across the samples of arguments, producing a signal of the output
of `fn`. Shorter signals are padded to accommodate the longest finite-length
signal. The function `fn` should treat each argument as a single number and
return a single number. This operation is broadcast across all channels of
the input. It is expected to be a type stable function.

## Cross-channel functions

The function is normally broadcast across channels, but if you wish to treat
each channel separately you can set `bychannel=false`. In this case the
inputs to `fn` will be objects supporting `getindex` (tuples or arrays) of
all channel values for a given sample, and `fn` should return a type-stable
tuple value (for a multi-channle or single-channel result) or a number (for a
signle-channel result only). For example, the following would swap the left
and right channels.

```julia
x = rand(10,2)
swapped = mapsignal(x,bychannel=false) do (left,right)
    right,left
end
```

## Padding

Padding determines how samples past the end of shorter signals are reported.
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

    xs = uniform(xs,channels=true)
    fs = samplerate(xs[1])
    lens = nsamples.(xs) |> collect
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
struct SignalOpCheckpoint{Ch,C} <: AbstractCheckpoint
    leader::Int
    channels::Ch
    children::C
end
checkindex(x::SignalOpCheckpoint) = checkindex(x.children[x.leader])

const MAX_CHANNEL_STACK = 64

function checkpoints(x::MapSignal,offset,len)
    # generate all children's checkpoints
    child_checks = map(x.padded_signals) do arg
        checkpoints(arg,offset,len)
    end 
    indices = mapreduce(@λ(checkindex.(_)),vcat,child_checks) |> sort!
    
    # combine children checkpoints in order
    child_indices = ones(Int,length(x.padded_signals))
    mapreduce(vcat,indices) do index
        mapreduce(vcat,enumerate(x.padded_signals)) do (i,arg)
            while checkindex(child_checks[i][child_indices[i]]) < index 
                child_indices[i] == length(child_checks[i]) && break
                child_indices[i] += 1
            end

            # enforce the invariant that the leader is the highest (or tied)
            # index
            if checkindex(child_checks[i][child_indices[i]]) > index
                child_indices[i] > 1
                child_indices[i] -= 1
            end

            if checkindex(child_checks[i][child_indices[i]]) == index
                children = map(@λ(_[_]),child_checks,child_indices) |> Tuple

                nch = ntuple_N(typeof(x.val))
                if nch > MAX_CHANNEL_STACK && (x.fn isa FnBr)
                    channels = Array{channel_eltype(x)}(undef,nch)
                else
                    channels = nothing
                end

                [SignalOpCheckpoint(i,channels,children)]
            else
                []
            end
        end
    end
end
beforecheckpoint(x::MapSignal,check::SignalOpCheckpoint,len) =
    beforecheckpoint(x,check.children[check.leader],len)
aftercheckpoint(x::MapSignal,check::SignalOpCheckpoint,len) =
    aftercheckpoint(x,check.children[check.leader],len)

struct OneSample
end
const one_sample = OneSample()
writesink!(::OneSample,i,val) = val

# expand the N == 2 case just to amke debugging
# easier (this is exactly what the generated function
# would produce)

# Base.@propagate_inbounds function sampleat!(result,
#     x::MapSignal{<:FnBr,2,2},i,j,check)

#     _1 = sampleat!(one_sample,x.padded_signals[1],1,j,check.children[1])
#     _2 = sampleat!(one_sample,x.padded_signals[2],1,j,check.children[2])

#     y_1 = x.fn(_1[1],_2[1])
#     y_2 = x.fn(_1[2],_2[2])
#     writesink!(result,i,(y_1,y_2))
# end

trange(::Val{N}) where N = (trange(Val(N-1))...,N)
trange(::Val{1}) = (1,)

__sample_signals(::Int,::Tuple,::Tuple,::Val{0}) = ()
function __sample_signals(j::Int,sigs::Tuple,checks::Tuple,::Val{N}) where N
    (__sample_signals(j,sigs,checks,Val{N-1}())...,
        sampleat!(one_sample,sigs[N],1,j,checks[N]))
end

Base.@propagate_inbounds function sampleat!(result,
    x::MapSignal{<:FnBr,N,C},i,j,check::SignalOpCheckpoint{<:Nothing}) where {N,C}

    inputs = __sample_signals(j,x.padded_signals,check.children,Val{N}())

    channels = map(trange(Val{C}())) do ch
        x.fn(map(@λ(_[ch]),inputs)...)
    end
    writesink!(result,i,channels)
end

Base.@propagate_inbounds function sampleat!(result,
    x::MapSignal{<:FnBr,N,C},i,j,check::SignalOpCheckpoint{<:Array}) where {N,C}

    inputs = __sample_signals(j,x.padded_signals,check.children,Val{N}())

    map!(check.channels,1:C) do ch
        x.fn(map(@λ(_[ch]),inputs)...)
    end
    writesink!(result,i,check.channels)
end

Base.@propagate_inbounds function sampleat!(result,
    x::MapSignal{<:Any,N},i,j,check) where N

    inputs = __sample_signals(j,x.padded_signals,check.children,Val{N}())
    writesink!(result,i,x.fn(inputs...))
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
        list_layout(signaltile.(x.signals),par=(mapstring(x.fn),")"))
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

Find the product, on a per-sample basis, for all signals `xs`, using
[`mapsignal`](@ref).

"""
amplify(y) = x -> amplify(x,y)
amplify(xs...) = mapsignal(*,xs...)
mapstring(::FnBr{<:typeof(*)}) = "amplify("

"""

    addchannel(xs...)

Concatenate the channels of all signals into one signal with
`sum(nchannels,xs)` channels, using [`mapsignal`](@ref).

"""
addchannel(y) = x -> addchannel(x,y)
addchannel(xs...) = mapsignal(tuplecat,xs...;bychannel=false)
tuplecat(a,b) = (a...,b...)
tuplecat(a,b,c,rest...) = reduce(tuplecat,(a,b,c,rest...))
mapstring(::typeof(tuplecat)) = "addchannel("

"""

    channel(x,n)

Select channel `n` of signal `x`, as a single channel signal, using
[`mapsignal`](@ref).

"""
channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(GetChanFn(n),x,bychannel=false)
struct GetChanFn; n::Int; end
(fn::GetChanFn)(x) = x[fn.n]
mapstring(fn::GetChanFn) = string("channel(",fn.n)
