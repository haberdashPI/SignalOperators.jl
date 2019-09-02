using Statistics

similar_helper(sig) = similar_helper(eltype(sig),length(sig))
similar_helper(x::Type{<:NTuple{M,T}},N) where {M,T} = Array{T}(undef,N,M)


"""
    sink(to=Array])
    sink(signal,to=Array])

Creats a given type of object from a signal. By default it is an array with
time as the rows and channels as the columns. If a filename is specified, the
signal is written to the given file. If given a type (e.g. `AxisArray`) the
signal is written to that type. 

If no signal is given, creates a single argument function which, when called,
sends the given signal to the sink. (e.g. `mysignal |> sink("result.wav")`)

"""
sink(x) = sink(x,SignalTrait(x))

function sink(x,s::IsSignal{El}) where El
    smp = samples(x)
    times = Axis{:time}(range(0s,length=nsamples(x),step=s/samplerate(x)))
    channels = Axis{:channel}(1:nchannels(x))
    result = sink(x,s,smp,Iterators.IteratorSize(x))
    MetaArray(IsSignal{El}(samplerate(x)),result)
end
sink(x, ::Nothing) = error("Don't know how to interpret value as an array: $x")
function sink(xs,::IsSignal,smp,::Iterators.HasLength)
    result = similar_helper(smp)
    samples_to_result!(result,smp)
end
function samples_to_result!(result,smp)
    for (i,x) in enumerate(smp)
        result[i,:] .= x
    end
    result
end
function sink(x,::IsSignal,smp,::Iterators.IsInfinite)
    error("Cannot store infinite signal in an array. (Use `until`?)")
end

abstract type WrappedSignal{T} <: AbstractSignal
end

"""
    childsignal(x)

Retrieve the signal wrapped by x of type `WrappedSignal`
"""
function childsignal
end
samplerate(x::WrappedSignal) = samplerate(childsignal(x))
SignalTrait(x::WrappedSignal) = SignalTrait(childsignal(x))

Base.Iterators.IteratorEltype(::Type{<:WrappedSignal}) = Iterators.HasEltype()
Base.eltype(::Type{<:WrappedSignal{T}}) where T = signal_eltype(T)
Base.Iterators.IteratorSize(::Type{<:WrappedSignal{T}}) where T =
    Iterators.IteratorSize(T)
Base.length(x::WrappedSignal) = length(childsignal(x))