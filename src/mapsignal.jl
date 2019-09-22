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
    across_channels::Bool
end

function SignalOp(fn::Fn,val::El,len::L,signals::Si,
    samplerate::Fs,padding::Pd,blocksize::Int,across_channels::Bool) where 
        {Fn,El,L,Si,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    N = El == NoValues ? 0 : length(signals)
    padded_signals = pad.(signals,Ref(padding))
    PSi = typeof(padded_signals)
    SignalOp{Fn,N,T,Fs,El,L,Si,Pd,PSi}(fn,val,len,signals,samplerate,padding,
        padded_signals,blocksize,across_channels)
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
        mapsignal(x.fn,tosamplerate.(x.signals,fs,blocksize=blocksize)...,
            padding=x.padding,across_channels=x.across_channels,
            blocksize=x.blocksize)
    else
        # resample output if we are upsampling
        tosamplerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

tosamplerate(x::SignalOp,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    mapsignal(x.fn,tosamplerate.(x.signals,fs,blocksize=blocksize)...,
        padding=x.padding,across_channels=x.across_channels,
        blocksize=x.blocksize)

"""
    mapsignal(fn,arguments...;padding,across_channels)

Apply `fn` across the samples of arguments, producing a signal of the output
of `fn`. Shorter signals are padded to accomodate the longest finite-length
signal. The function `fn` can return a single number or a tuple of numbers.
In either case it is expected to be a type stable function.

## Cross-channel functions

The function is normally broadcast across channels, but if you wish to treat
each channel seperately you can set `across_channels=true`. In this case the
inputs to `fn` will be tuples of all channel values for a given sample, and
`fn` should return a type-stable tuple value. For exmpale, the following
would swap the left and right channels.

```julia
x = rand(10,2)
swapped = mapsignal(x,across_channels=true) do (left,right)
    right,left
end
```

## Padding

Padding determines how samples past the end of shorter signals are reported.
You can pass a number or a function of a type (e.g. `zero`) to `padding`. The
default for the four basic arithematic operators is their identity (`one` for
`*` and `zero` for `+`). These defaults are set on the basis of `fn` using
`default_pad(fn)`. A fallback implementation of `default_pad` returns `zero`.

To define a new default for a specific function, just create a new method of
`default_pad(fn)`

```julia

myfun(x) = 2x + 3
SignalOperators.default_pad(myfun) = one

```

"""
function mapsignal(fn,xs...;padding = default_pad(fn),across_channels = false,
    blocksize=default_blocksize)

    xs = uniform(xs)
    fs = samplerate(xs[1])
    lens = nsamples.(xs) |> collect
    len = all(isinf,lens) ? inflen :
            any(ismissing,lens) ? missing :
            maximum(filter(!isinf,lens)) 

    vals = testvalue.(xs)
    if !across_channels
        fnbr(vals...) = fn.(vals...)
        SignalOp(fnbr,astuple(fnbr(vals...)),len,xs,fs,padding,blocksize,
            across_channels)
    else
        SignalOp(fn,astuple(fn(vals...)),len,xs,fs,padding,blocksize,
            across_channels)
    end
end
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
writesink(::OneSample,i,val) = val

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
        writesink(result,i,y)
   end
end

default_pad(x) = zero
default_pad(::typeof(+)) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(-)) = zero
default_pad(::typeof(/)) = one

"""

    mix(xs...)

Sum all signals together, using [`mapsignal`](@ref)

"""
mix(x) = y -> mix(x,y)
mix(xs...) = mapsignal(+,xs...)

"""

    amplify(xs...)

Multipy all signals by one another, using [`mapsignal`](@ref)

"""
amplify(x) = y -> amplify(x,y)
amplify(xs...) = mapsignal(*,xs...)

"""

    addchannel(xs...)

Concatenate the channels of all signals into one signal with
`sum(nchannels,xs)` channels.

"""
addchannel(y) = x -> addchannel(x,y)
addchannel(xs...) = mapsignal(tuplecat,xs...;across_channels=true)
tuplecat(a,b) = (a...,b...)
tuplecat(a,b,c,rest...) = reduce(tuplecat,(a,b,c,rest...))

"""

    channel(x,n)

Select channel `n` of signal `x`, as a single channel signal.

"""
channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(@λ(_[n]), x,across_channels=true)
