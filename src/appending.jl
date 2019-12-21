export append, prepend, pad

struct AppendSignals{Si,Sis,T,L} <: WrappedSignal{Si,T}
    signals::Sis
    len::L
end
SignalTrait(x::Type{T}) where {Si,T <: AppendSignals{Si}} =
    SignalTrait(x,SignalTrait(Si))
function SignalTrait(x::Type{<:AppendSignals{Si,Rst,T,L}},
        ::IsSignal{T,Fs}) where {Si,Rst,T,L,Fs}
    IsSignal{T,Fs,L}()
end
child(x::AppendSignals) = x.signals[1]
nframes(x::AppendSignals) = x.len
duration(x::AppendSignals) = sum(duration.(x.signals))

root(x::AppendSignals) = reduce(mergeroot,root.(x.signals))

"""
    append(x,y,...)

Append a series of signals, one after the other.
"""
append(y) = x -> append(x,y)
"""
    prepend(x,y,...)

Prepend the series of signals: `prepend(xs...)` is equivalent to
`append(reverse(xs)...)`.

"""
prepend(x) = y -> append(x,y)
prepend(x,y,rest...) = prepend(reverse((x,y,rest...)...))

function append(xs...)
    xs = uniform(xs,channels=true)
    if any(isinf ∘ nframes,xs[1:end-1])
        error("Cannot append to the end of an infinite signal")
    end

    El = promote_type(channel_eltype.(xs)...)
    xs = map(xs) do x
        if channel_eltype(x) != El
            toeltype(x,El)
        else
            x
        end
    end

    len = sum(nframes,xs)
    AppendSignals{typeof(xs[1]),typeof(xs),El,typeof(len)}(xs, len)
end
toframerate(x::AppendSignals,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    append(toframerate.(x.signals,fs;blocksize=blocksize)...)
toframerate(x::AppendSignals,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = append(toframerate.(x.signals,fs;blocksize=blocksize)...)

struct AppendBlock{S,C}
    signal::S
    child::C
    k::Int
end
child(x::AppendBlock) = x.child
nframes(x::AppendBlock) = nframes(x.child)
@Base.propagate_inbounds frame(::AppendSignals,x::AppendBlock,i) =
    frame(x.signal,x.child,i)

function nextblock(x::AppendSignals,maxlen,skip)
    child = nextblock(x.signals[1],maxlen,skip)
    advancechild(x,maxlen,skip,1,child)
end
function nextblock(x::AppendSignals,maxlen,skip,block::AppendBlock)
    childblock = nextblock(x.signals[block.k],maxlen,skip,child(block))
    advancechild(x,maxlen,skip,block.k,childblock)
end

function advancechild(x::AppendSignals,maxlen,skip,k,childblock)
    K = length(x.signals)
    while k < K && isnothing(childblock)
        k += 1
        childblock = nextblock(x.signals[k],maxlen,skip)
    end
    if !isnothing(childblock)
        AppendBlock(x.signals[k],childblock,k)
    end
end

Base.show(io::IO,::MIME"text/plain",x::AppendSignals) = pprint(io,x)
function PrettyPrinting.tile(x::AppendSignals)
    if length(x.signals) == 2
        child = signaltile(x.signals[1])
        operate = literal("append(") * signaltile(x.signals[2]) * literal(")") |
            literal("append(") / indent(4) * signaltile(x.signals[2]) / literal(")")
        tilepipe(child,operate)
    else
        list_layout(map(signaltile,x.signals),prefix="append",sep=",",sep_brk=",")
    end
end
signaltile(x::AppendSignals) = PrettyPrinting.tile(x)
