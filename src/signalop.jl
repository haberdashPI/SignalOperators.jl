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

function mapsignal(fn,xs...;padding = default_pad(fn))
    xs = uniform(xs)   
    @show xs
    fs = samplerate(xs[1])
    if any(!infsignal,xs) 
        if filter(!infsignal,collect(xs)) |> @λ(any(!=(_xs[1]),_xs[2:end]))
            longest = argmax(map(x -> infsignal(x) ? 0 : nsamples(x),xs))
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
        vals = map(@λ(_[1]),results)
        y = fn.(vals...) 
        SignalOp(fn,y,len,(true,map(@λ(_[2]),results)),sm,fs)
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
            x.fn.(vals...), (false,map(@λ(_[2]),results))
        end
    end
end
Base.Iterators.IteratorEltype(::Type{<:SignalOp}) = HasEltype()
Base.eltype(::Type{<:SignalOp{<:Any,El}}) where El = El
Base.Iterators.IteratorSize(::Type{SignalOp{<:Any,<:Any,Nothing}}) = IsInfinite()
Base.Iterators.IteratorSize(::Type{SignalOp{<:Any,<:Any,Int}}) = HasLength()
Base.length(x::SignalOp) = x.len

default_pad(x) = zero
default_pad(::typeof(+)) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(-)) = zero
default_pad(::typeof(/)) = one

mix(x) = ys -> mix(x,y)
mix(xs...) = mapsignal(+,xs...)

amplify(x) = y -> amplify(x,y)
amplify(xs...) = mapsignal(*,xs...)

addchannel(y) = x -> addchannel(x,y)
addchannel(xs...) = mapsignal(tuple,xs...)

channel(n) = x -> channel(x,n)
channel(x,n) = mapsignal(@λ(_[1]), x)
