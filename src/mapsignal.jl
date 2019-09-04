using Unitful
export mapsignal, mix, amplify, addchannel

################################################################################
# binary operators

struct SignalOp{Fn,Fs,El,L,Args,Pd} <: AbstractSignal
    fn::Fn
    val::El
    len::L
    args::Args
    samplerate::Fs
    padding::Pd
end
struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:SignalOp{<:Any,Fs,El,L}}) where {Fs,El,L} = 
    IsSignal{numpte_T(El),Fs,L}()
nsamples(x::SignalOp) = x.len
nchannels(x::SignalOp) = length(x.state)
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
function mapsignal(fn,xs...;padding = default_pad(fn),across_channels = false)
    xs = uniform(xs)   
    fs = samplerate(xs[1])
    finite = findall(!infsignal,xs)
    if !isempty(finite)
        if any(@λ(!=(xs[finite[1]],_)),xs[finite[2:end]])
            longest = argmax(map(i -> nsamples(xs[i]),finite))
            xs = (map(pad(padding),xs[1:longest-1])..., xs[longest],
                  map(pad(padding),xs[longest+1:end])...)
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
            fnbr(vals) = fn.(vals...)
            SignalOp(fnbr,astuple(fnbr(vals)),len,xs,fs,padding)
        else
            SignalOp(fn,astuple(fn(vals...)),len,xs,fs,padding)
        end
    end
end
testvalue(x) = Tuple(zero(channel_eltype(x)) for _ in 1:nchannels(x))

block_length(x::SignalOp) = minimum(block_length.(x.args))

struct OneSample
    ch::Int
end
Base.size(x::OneSample) = (1,x.ch)
Base.dotview(result::OneSample,::Number,::Colon) = result
Base.copyto!(result::OneSample,vals::Broadcast.Broadcasted) = vals.args[1]

@Base.propagate_inbounds function sinkat!(result::AbstractArray,x::SignalOp,
    ::IsSignal,i::Number,j::Number)

    vals = map(x.args) do arg
        sinkat!(OneSample,arg,SignalTrait(arg),1,j)
    end
    result[i,:] .= x.fn(vals...)
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
