using Unitful
export mapsignal, mix, amplify, addchannel

################################################################################
# binary operators

struct SignalOp{Fn,El,L,S,A} <: AbstractSignal
    fn::Fn
    val::El
    len::L
    state::S
    samples::A
    samplerate::Float64
end
struct NoValues
end
novalues = NoValues()
SignalTrait(x::SignalOp{<:Any,El}) where El = IsSignal{El}(x.samplerate)

function mapsignal(fn,xs...;padding = default_pad(fn),across_channels = false)
    xs = uniform(xs)   
    fs = samplerate(xs[1])
    finite = findall(!infsignal,xs)
    if !isempty(finite)
        if any(!=(xs[finite[1]]),xs[finite[2:end]])
            longest = argmax(map(i -> nsamples(xs[i]),finite))
            xs = (map(pad(padding),xs[1:longest-1])..., xs[longest],
                  map(pad(padding),xs[longest+1:end])...)
            len = nsamples(xs[longest])
        else
            len = nsamples(xs[1])
        end
    else
        len = nothing
    end
    sm = samples.(xs)
    results = iterate.(sm)
    if any(isnothing,results)
        SignalOp(fn,novalues,len,(true,nothing),sm,fs)
    else
        if !across_channels
            fnbr(vals...) = fn.(vals...)
            vals = map(@λ(_[1]),results)
            y = astuple(fnbr(vals...))
            SignalOp(fnbr,y,len,(true,map(@λ(_[2]),results)),sm,fs)
        else
            vals = map(@λ(_[1]),results)
            y = astuple(fn(vals...))
            SignalOp(fn,y,len,(true,map(@λ(_[2]),results)),sm,fs)
        end
    end
end
Base.iterate(x::SignalOp{<:Any,NoValues}) = nothing
function Base.iterate(x::SignalOp,(use_val,states) = x.state)
    if use_val
        x.val, (false,states)
    else
        results = iterate.(x.samples,states)
        if any(isnothing,results)
            nothing
        else
            vals = map(@λ(_[1]),results)
            astuple(x.fn(vals...)), (false,map(@λ(_[2]),results))
        end
    end
end
Base.Iterators.IteratorEltype(::Type{<:SignalOp}) = Iterators.HasEltype()
Base.eltype(::Type{<:SignalOp{<:Any,El}}) where El = El
Base.Iterators.IteratorSize(::Type{<:SignalOp{<:Any,<:Any,Nothing}}) = Iterators.IsInfinite()
Base.Iterators.IteratorSize(::Type{<:SignalOp{<:Any,<:Any,Int}}) = Iterators.HasLength()
Base.length(x::SignalOp) = x.len

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
addchannel(xs...) = mapsignal(tuple,xs...;across_channels=true)

channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(@λ(_[1]), x,across_channels=true)
