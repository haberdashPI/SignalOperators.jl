using Unitful
export mapsignal, mix, amplify, addchannel, channel

################################################################################
# binary operators

struct SignalOp{Fn,N,T,Fs,El,L,Si,Pd,PSi} <: AbstractSignal{T}
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

function SignalOp(fn::Fn,val::El,len::L,signals::Si,
    samplerate::Fs,padding::Pd,blocksize::Int,bychannel::Bool) where 
        {Fn,El,L,Si,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    N = El == NoValues ? 0 : length(signals)
    padded_signals = pad.(signals,Ref(padding))
    PSi = typeof(padded_signals)
    SignalOp{Fn,N,T,Fs,El,L,Si,Pd,PSi}(fn,val,len,signals,samplerate,padding,
        padded_signals,blocksize,bychannel)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:SignalOp{<:Any,<:Any,T,Fs,L}}) where {Fs,T,L} = 
    IsSignal{T,Fs,L}()
nsamples(x::SignalOp) = x.len
nchannels(x::SignalOp) = length(x.val)
samplerate(x::SignalOp) = x.samplerate
function duration(x::SignalOp)
    durs = duration.(x.signals) |> collect
    all(isinf,durs) ? inflen :
        any(ismissing,durs) ? missing :
        maximum(filter(!isinf,durs))
end
function tosamplerate(x::SignalOp,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
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

tosamplerate(x::SignalOp,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    mapsignal(cleanfn(x.fn),tosamplerate.(x.signals,fs,blocksize=blocksize)...,
        padding=x.padding,bychannel=x.bychannel,
        blocksize=x.blocksize)

"""
    mapsignal(fn,arguments...;padding,bychannel)

Apply `fn` across the samples of arguments, producing a signal of the output
of `fn`. Shorter signals are padded to accommodate the longest finite-length
signal. The function `fn` can return a single number or a tuple of numbers.
In either case it is expected to be a type stable function.

## Cross-channel functions

The function is normally broadcast across channels, but if you wish to treat
each channel separately you can set `bychannel=false`. In this case the
inputs to `fn` will be objects supporting `getindex` (tuples or arrays) of
all channel values for a given sample, and `fn` should return a type-stable
tuple value. For example, the following would swap the left and right
channels.

```julia
x = rand(10,2)
swapped = mapsignal(x,bychannel=false) do (left,right)
    right,left
end
```

## Padding

Padding determines how samples past the end of shorter signals are reported.
You can pass a number or a function of a type (e.g. `zero`) to `padding`. The
default for the four basic arithmetic operators is their identity (`one` for
`*` and `zero` for `+`). These defaults are set on the basis of `fn` using
`default_pad(fn)`. A fallback implementation of `default_pad` returns `zero`.

To define a new default for a specific function, just create a new method of
`default_pad(fn)`

```julia

myfun(x) = 2x + 3
SignalOperators.default_pad(::typeof(myfun)) = one

```

"""
function mapsignal(fn,xs...;padding = default_pad(fn),bychannel=true,
    blocksize=default_blocksize)

    xs = uniform(xs)
    fs = samplerate(xs[1])
    lens = nsamples.(xs) |> collect
    len = all(isinf,lens) ? inflen :
            any(ismissing,lens) ? missing :
            maximum(filter(!isinf,lens)) 

    vals = testvalue.(xs)
    if bychannel
        fn = FnBr(fn)
    end
    SignalOp(fn,astuple(fn(vals...)),len,xs,fs,padding,blocksize,
        bychannel)
end

struct FnBr{Fn}
    fn::Fn
end
(fn::FnBr)(xs...) = fn.fn.(xs...)
cleanfn(x) = x
cleanfn(x::FnBr) = x.fn

testvalue(x) = Tuple(zero(channel_eltype(x)) for _ in 1:nchannels(x))
struct SignalOpCheckpoint{N,C} <: AbstractCheckpoint
    leader::Int
    children::C
end
checkindex(x::SignalOpCheckpoint) = checkindex(x.children[x.leader])

function checkpoints(x::SignalOp,offset,len)
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
                children = map(@λ(_[_]),child_checks,child_indices)
                N,C = ntuple_N(typeof(x.val)),typeof(children)
                [SignalOpCheckpoint{N,C}(i,children)]
            else
                []
            end
        end
    end
end
beforecheckpoint(x::SignalOp,check::SignalOpCheckpoint,len) =
    beforecheckpoint(x,check.children[check.leader],len)
aftercheckpoint(x::SignalOp,check::SignalOpCheckpoint,len) =
    aftercheckpoint(x,check.children[check.leader],len)

struct OneSample
end
one_sample = OneSample()
writesink!(::OneSample,i,val) = val

# TODO: this should just be a generated function
Base.@propagate_inbounds @generated function sampleat!(result,
    x::SignalOp{<:Any,N},sig,i,j,check) where N

   vars = [Symbol(string("_",i)) for i in 1:N] 
   quote
        $((:($(vars[i]) = 
            sampleat!(one_sample,x.padded_signals[$i],
                SignalTrait(x.padded_signals[$i]),1,j,
                check.children[$i])) for i in 1:N)...)
        y = x.fn($(vars...))
        writesink!(result,i,y)
   end
end

default_pad(x) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(/)) = one

Base.show(io::IO,::MIME"text/plain",x::SignalOp) = pprint(io,x)
function PrettyPrinting.tile(x::SignalOp)
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
signaltile(x::CutApply) = PrettyPrinting.tile(x)
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
