using Unitful
export mapsignal, mix, amplify, addchannel

################################################################################
# binary operators

struct SignalOp{Fn,Fs,El,L,Args,Pd,T} <: AbstractSignal{T}
    fn::Fn
    val::El
    len::L
    args::Args
    samplerate::Fs
    padding::Pd
    blocksize::Int
end

function SignalOp(fn::Fn,val::El,len::L,args::Args,
    samplerate::Fs,padding::Pd,blocksize::Int) where {Fn,El,L,Args,Fs,Pd}

    SignalOp{Fn,Fs,El,L,Args,Pd,ntuple_T(El)}(fn,val,len,args,
        samplerate,padding,blocksize)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:SignalOp{<:Any,Fs,El,L}}) where {Fs,El,L} = 
    IsSignal{ntuple_T(El),Fs,L}()
nsamples(x::SignalOp) = x.len
nchannels(x::SignalOp) = length(x.val)
samplerate(x::SignalOp) = x.samplerate
function tosamplerate(x::SignalOp,s::IsSignal,c::ComputedSignal,fs)
    if ismissing(x.samplerate) || ismissing(fs) || fs < x.samplerate
        # resample input if we are downsampling 
        mapsignal(x.fn,tosamplerate.(x.args,fs)...,padding=x.padding)
    else
        # resample output if we are upsampling
        tosamplerate(x,s,DataSignal(),fs)
    end
end

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
    blocksize=default_block_size)

    xs = uniform(xs)   
    fs = samplerate(xs[1])
    finite = findall(!infsignal,xs)
    if !isempty(finite)
        if any(@λ(!=(xs[finite[1]],_)),xs[finite[2:end]])
            longest = argmax(map(i -> nsamples(xs[i]),finite))
            xs = map(enumerate(xs)) do (i,x)
                if infsignal(x) || nsamples(x) == nsamples(xs[longest])
                    x
                else
                    map(pad(padding),x)
                end
            end

            len = nsamples(xs[longest])
        else
            len = nsamples(xs[finite[1]])
        end
    else
        len = nothing
    end
    if !isnothing(len) && len == 0
        SignalOp(fn,novalues,len,(true,nothing),sm,fs)
    else
        vals = testvalue.(xs)
        if !across_channels
            fnbr(vals...) = fn.(vals...)
            SignalOp(fnbr,astuple(fnbr(vals...)),len,xs,fs,padding,blocksize)
        else
            SignalOp(fn,astuple(fn(vals...)),len,xs,fs,padding,blocksize)
        end
    end
end
testvalue(x) = Tuple(zero(channel_eltype(x)) for _ in 1:nchannels(x))
struct SignalOpCheckpoint{C}
    leader::Int
    children::C
end
checkindex(x::SignalOpCheckpoint) = checkindex(x.children[x.leader])

function checkpoints(x::SignalOp,offset,len)
    # generate all children's checkpoints
    child_checks = map(x.args) do arg
        checkpoints(arg,offset,len)
    end 
    indices = mapreduce(@λ(checkindex.(_)),vcat,child_checks) |> sort!
    
    # combine children checkpoints in order
    child_indices = ones(Int,length(x.args))
    mapreduce(vcat,indices) do index
        mapreduce(vcat,enumerate(x.args)) do (i,arg)
            while checkindex(child_checks[i][child_indices[i]]) < index 
                child_indices[i] == length(child_checks[i]) && break
                child_indices[i] += 1
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
function beforecheckpoint(x::SignalOp,check::SignalOpCheckpoint,len)
    beforecheckpoint(x,check.children[check.leader],len)
end

block_length(x::SignalOp) = minimum(block_length.(x.args))

struct OneSample
end
one_sample = OneSample()
writesink(::OneSample,i,val) = val

@Base.propagate_inbounds function sampleat!(result,x::SignalOp,sig,i,j,check)
    vals = map(enumerate(x.args)) do (i,arg)
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
channel(x,n) = mapsignal(@λ(_[1]), x,across_channels=true)
