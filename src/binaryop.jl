using Unitful

################################################################################
# binary operators

struct SignalOp{Fn,El,L,S,A}
    fn::Fn
    val::El
    len::L
    state::S
    samples::A
end
signal_length(x::SignalOp) = (x.len-1)*frames
nsamples(x::SignalOp) = x.len

signalop(fn,x,kwds...) = y -> signalop(fn,x,y;kwds...)
function signalop(fn,xs...;padding = default_pad(fn))
    xs = uniform(xs)   
    if any(!isinf,xs)
        longest = argmax(map(x -> isinf(nsamples(x)) ? 0 : nsamples(x),xs))
        xs = (map(pad(padding),xs[1:longest-1])..., xs[longest],
              map(pad(padding),xs[longest+1:end])...)
        len = nsamples(xs[longest])
    else
        len = infinite_length
    end
    sm = samples.(xs)
    result = iterate.(sm)
    if isnothing(result)
        error("Empty signals can't be operated on.")
    else
        vals, state = result
        y = x.fn.(vals...) 
        SignalOp(fn,val,len,iterate(sm,state),sm)
    end
end
function Base.iterate(x::SignalOp,result = x.state)
    if !any(isnothing,result)
        vals, state = result
        x.fn.(vals...), iterate.(x.samples, state)
    end
end
Base.IteratorEltype(x::SignalOp) = HasEltype()
Base.eltype(x::SignalOp{<:Any,El}) where El = El
Base.IteratorSize(x::SignalOp{<:Any,<:Any,InfiniteLength}) = IsInfinite()
Base.IteratorSize(x::SignalOp{<:Any,<:Any,Int}) = HasLength()
Base.length(x::SignalOp) = x.len

default_pad(::typeof(+)) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(-)) = zero
default_pad(::typeof(/)) = one

mix(x) = (ys...) -> mix(x,ys...)
mix(xs...) = signalop(+,xs...)

amplify(x) = (ys...) -> amplify(x,ys...)
amplify(xs...) = signalop(+,xs...)