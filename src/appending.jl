export Append, Prepend, append, prepend

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
nframes_helper(x::AppendSignals) = x.len
duration(x::AppendSignals) = sum(duration.(x.signals))

root(x::AppendSignals) = reduce(mergeroot,root.(x.signals))

"""
    Append(x,y,...)

Append a series of signals, one after the other.
"""
Append(y) = x -> Append(x,y)
"""
    Prepend(x,y,...)

Prepend the series of signals: `Prepend(xs...)` is equivalent to
`Append(reverse(xs)...)`.

"""
Prepend(x) = y -> Append(x,y)
Prepend(x,y,rest...) = Append(reverse((x,y,rest...))...)

"""
    append(x,y,...)

Equivalent to `sink(Append(x,y,...))`

## See also

[`Append`](@ref)

"""
append(xs...) = sink(Append(xs...))

"""
    prepend(x,y,...)

Equivalent to `sink(Prepend(x,y,...))`

## See also

[`Prepend`](@ref)

"""
prepend(xs...) = sink(Prepend(xs...))

function Append(xs...)
    xs = Uniform(xs,channels=true)
    if any(isknowninf ∘ nframes,xs[1:end-1])
        error("Cannot Append to the end of an infinite signal")
    end

    El = promote_type(sampletype.(xs)...)
    xs = map(xs) do x
        if sampletype(x) != El
            ToEltype(x,El)
        else
            x
        end
    end

    len = any(isknowninf ∘ nframes,xs) ? inflen : sum(nframes,xs)
    AppendSignals{typeof(xs[1]),typeof(xs),El,typeof(len)}(xs, len)
end
ToFramerate(x::AppendSignals,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    Append(ToFramerate.(x.signals,fs;blocksize=blocksize)...)
ToFramerate(x::AppendSignals,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = Append(ToFramerate.(x.signals,fs;blocksize=blocksize)...)

function iterateblock(x::AppendSignals,N,state=(1,))
    K = length(x.signals)
    k = state[1]
    childblock = iterateblock(x.signals[k],N,Base.tail(state)...)
    while k < K && isnothing(childblock)
        k += 1
        childblock = iterateblock(x.signals[k],N)
    end
    if !isnothing(childblock)
        data, childstate = childblock
        return data, (k, childstate)
    end
end

Base.show(io::IO,::MIME"text/plain",x::AppendSignals) = pprint(io,x)
function PrettyPrinting.tile(x::AppendSignals)
    if length(x.signals) == 2
        child = signaltile(x.signals[1])
        operate = literal("Append(") * signaltile(x.signals[2]) * literal(")") |
            literal("Append(") / indent(4) * signaltile(x.signals[2]) / literal(")")
        tilepipe(child,operate)
    else
        list_layout(map(signaltile,x.signals),prefix="Append",sep=",",sep_brk=",")
    end
end
signaltile(x::AppendSignals) = PrettyPrinting.tile(x)
