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
        if !across_channels
            fnbr(vals) = fn.(vals...)
            y = astuple(fnbr(vals))
            SignalOp(fnbr,y,len,xs,fs,padding)
        else
            vals = map(@λ(_[1]),results)
            y = astuple(fn(vals...))
            SignalOp(fn,y,len,xs,fs,padding)
        end
    end
end
block_length(x::SignalOp) = maximum(block_length.(x.args))

init_block(x,n) = init_block(x,block_length(x))
init_block(x,n,::NoBlock) = OneSample()
init_block(x,n,block::Block) = Array{eltype(x)}(undef,n,nchannels(x))

struct OneSample
    ch::Int
end
Base.size(x::OneSample) = (1,x.ch)
Base.dotview(result::OneSample,::Number,::Colon) = result
Base.copyto!(result::OneSample,vals::Broadcast.Broadcasted) = vals.args[1]
sink!(buffer::OneSample,x,sig,offset,block) = block.min

@Base.propagate_inbounds frombuffer(buffer::OneSample,x,sig,i,offset) = 
    sinkat!(buffer,x,sig,1,i+offset)

load_buffer!(buffer::Array,x,sig,offset,block) = 
    sink!(buffer,x,sig,offset,block)
@Base.propagate_inbounds frombuffer(buffer::Array,x,sig,i,offset) =
    view(buffer,i,:)

function sink!(result::AbstractArray,x::SignalOp,sig::IsSignal,offset::Number,
    block::Block)
    sink!(result,x,sig,offset,block,init_block.(x.args,n))
end

function sink!(result::AbstractArray,x::SignalOp,sig::IsSignal,
    sink_offset::Number, block::Block, buffers)

    offset = 0
    while offset < size(result,1)
        len = min(block.min,size(result,1) - offset)
        mapreduce(min,zip(buffers,x.args);init=len) do (len,(buffer,arg))
            min(len,sink!(buffer,arg,SignalTrait(arg),sink_offset + offset,block))
        end

        @simd @inbounds for i in 1:len
            vals = map(zip(buffers,x.args)) do (buffer,arg)
                frombuffer(buffer,arg,SignalTrait(arg),i,sink_offset + offset)
            end

            result[i+offset,:] .= x.fn(vals...)
        end
        offset += len
    end
end

@Base.propagate_inbounds function sinkat!(result::AbstractArray,x::SignalOp,
    ::IsSignal,i::Number,j::Number)

    vals = map(x.args) do arg
        sinkat!(OneSample,arg,SignalTrait(arg),1,j)
    end
    result[i,:] .= x.fn(vals...)
end

@Base.propagate_inbounds function signal_setindex!(result,ris,x::SignalOp,xis)
    @inbounds for (ri,xi) in zip(ris,xis)
        signal_setindex!(result,ri,x,xi)
    end
end
@Base.propagate_inbounds function signal_setindex!(result,ri,x::SignalOp,xi::Number)
    map(@λ(signal_setindex!(_argval,1,_arg,xi)),x.argvals,x.args)
    result[ri,:] .= x.fn(x.argvals...)
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
