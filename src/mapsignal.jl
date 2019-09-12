using Unitful
export mapsignal, mix, amplify, addchannel, channel

################################################################################
# binary operators

struct SignalOp{Fn,Fs,El,L,Args,Pd,PArgs,T} <: AbstractSignal{T}
    fn::Fn
    val::El
    len::L
    args::Args
    samplerate::Fs
    padding::Pd
    pargs::PArgs
    blocksize::Int
    across_channels::Bool
end

function SignalOp(fn::Fn,val::El,len::L,args::Args,
    samplerate::Fs,padding::Pd,blocksize::Int,across_channels::Bool) where 
        {Fn,El,L,Args,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    pargs = pad.(args,Ref(padding))
    PArgs = typeof(pargs)
    SignalOp{Fn,Fs,El,L,Args,Pd,PArgs,T}(fn,val,len,args,samplerate,padding,
        pargs,blocksize,across_channels)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:SignalOp{<:Any,Fs,El,L}}) where {Fs,El,L} = 
    IsSignal{ntuple_T(El),Fs,L}()
nsamples(x::SignalOp) = x.len
nchannels(x::SignalOp) = length(x.val)
samplerate(x::SignalOp) = x.samplerate
function duration(x::SignalOp)
    durs = duration.(x.args) |> collect
    all(isinf,durs) ? inflen :
        any(ismissing,durs) ? missing :
        maximum(filter(!isinf,durs))
end
function tosamplerate(x::SignalOp,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize)
    if inHz(fs) < x.samplerate
        # resample input if we are downsampling 
        mapsignal(x.fn,tosamplerate.(x.args,fs,blocksize=blocksize)...,
            padding=x.padding,across_channels=x.across_channels,
            blocksize=x.blocksize)
    else
        # resample output if we are upsampling
        tosamplerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

tosamplerate(x::SignalOp,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    mapsignal(x.fn,tosamplerate.(x.args,fs,blocksize=blocksize)...,
        padding=x.padding,across_channels=x.across_channels,
        blocksize=x.blocksize)

"""
    mapsignal(fn,arguments...;padding,across_channels)

Apply `fn` across the samples of arguments, producing a signal of the output
of `fn`. All arguments are first interpreted as signals and reformatted so
they share the same sample rate and channel count. Shorter signals are padded
to accomodate the longest finite-length signal. The function `fn` can return a
single number or a tuple of numbers. In either case it is expected to be a
type stable function.

## Cross-channel functions

The function is normally broadcast across channels, but if you wish to treate
each channel seperately you can set `across_channels=true`.

## Padding

Padding determines how samples past the end of shorter signals are reported,
and is set to a function specific default using `default_pad`. There is a
fallback implementation which returns `zero`. `default_pad` should normally
return a function of a type (normally either `one` or `zero`), but can
optionally be a specific number.
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
struct SignalOpCheckpoint{C} <: AbstractCheckpoint
    leader::Int
    children::C
end
checkindex(x::SignalOpCheckpoint) = checkindex(x.children[x.leader])

function checkpoints(x::SignalOp,offset,len)
    # generate all children's checkpoints
    child_checks = map(x.pargs) do arg
        checkpoints(arg,offset,len)
    end 
    indices = mapreduce(@λ(checkindex.(_)),vcat,child_checks) |> sort!
    
    # combine children checkpoints in order
    child_indices = ones(Int,length(x.pargs))
    mapreduce(vcat,indices) do index
        mapreduce(vcat,enumerate(x.pargs)) do (i,arg)
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
                [SignalOpCheckpoint(i,children)]
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

@Base.propagate_inbounds function sampleat!(result,x::SignalOp,sig,i,j,check)
    vals = map(enumerate(x.pargs)) do (i,arg)
        sampleat!(one_sample,arg,SignalTrait(arg),1,j,check.children[i])
    end
    writesink(result,i,x.fn(vals...))
end

default_pad(x) = zero
default_pad(::typeof(+)) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(-)) = zero
default_pad(::typeof(/)) = one

mix(x) = y -> mix(x,y)
mix(xs...) = mapsignal(+,xs...)

amplify(x) = y -> amplify(x,y)
amplify(xs...) = mapsignal(*,xs...)

addchannel(y) = x -> addchannel(x,y)
addchannel(xs...) = mapsignal(tuplecat,xs...;across_channels=true)
tuplecat(a,b) = (a...,b...)
tuplecat(a,b,c,rest...) = reduce(tuplecat,(a,b,c,rest...))

channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(@λ(_[n]), x,across_channels=true)
