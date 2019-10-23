
"""
    sink([signal],[to=AxisArray];duration,samplerate)

Creates a given type of object (`to`) from a signal. By default it is an
`AxisArray` with time as the rows and channels as the columns. If a filename
is specified for `to`, the signal is written to the given file. If given a
type (e.g. `Array`) the signal is written to a value of that type.

# Sample Rate

The sample rate does not need to be specified, it will use either the sample
rate of `signal` or a default sample rate (which raises a warning). If
specified, the given sample rate is passed to [`signal`](@ref) when coercing
the input to a signal.

# Duration

You can limit the output of the given signal to the specified duration. If
this duration exceedes the duration of the passed signal an error will be
thrown.

"""
sink(to::Type=AxisArray;kwds...) = x -> sink(x,to;kwds...)
function sink(x::T,::Type{A}=AxisArray;
        duration=missing,
        samplerate=SignalOperators.samplerate(x)) where {T,A}

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)
    duration = coalesce(duration,nsamples(x)*samples)

    if isinf(duration)
        error("Cannot store infinite signal. Specify a finite duration when ",
            "calling `sink`.")
    end

    n = insamples(Int,maybeseconds(duration),SignalOperators.samplerate(x))
    if n > nsamples(x)
        error("Requested signal duration is too long for passed signal: $x.")
    end

    sink(x,SignalTrait(x),n,A)
end

function sink(x,sig::IsSignal{El},len::Number,::Type{<:Array}) where El
    result = Array{El}(undef,len,nchannels(x))
    sink!(result,x)
end
function sink(x,sig::IsSignal{El},len,::Type{<:AxisArray}) where El
    result = sink(x,sig,len,Array)
    times = Axis{:time}(range(0s,length=size(result,1),step=float(s/samplerate(x))))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(result,times,channels)
end
sink(x, ::IsSignal, ::Nothing, ::Type) = error("Don't know how to interpret value as a signal: $x")

"""
    sink!(array,x;[samplerate],[offset])

Write `size(array,1)` samples of signal `x` to `array`, starting from the sample after
`offset`. If no sample rate has been specified for `x` you can specify it
now, using `samplerate` (it will default to 44.1kHz).

"""
sink!(result::Union{AbstractVector,AbstractMatrix};kwds...) =
    x -> sink!(result,x;kwds...)
function sink!(result::Union{AbstractVector,AbstractMatrix},x;
    samplerate=SignalOperators.samplerate(x),offset=0)

    if ismissing(samplerate) && ismissing(SignalOperators.samplerate(x))
        @warn("No sample rate was specified, defaulting to 44.1 kHz.")
        samplerate = 44.1kHz
    end
    x = signal(x,samplerate)

    if nsamples(x)-offset < size(result,1)
        error("Signal is too short to fill buffer of length $(size(result,1)).")
    end
    x = tochannels(x,size(result,2))

    sink!(result,x,SignalTrait(x),offset)
end

abstract type AbstractCheckpoint{S}
end
struct EmptyCheckpoint{S} <: AbstractCheckpoint{S}
    n::Int
end
checkindex(x::EmptyCheckpoint) = x.n
child(x::Number) = x
checkindex(x::Number) = x+1

atcheckpoint(x,offset::Number,stopat) =
    offset ≥ stopat ? nothing : EmptyCheckpoint{typeof(x)}(1+offset)
atcheckpoint(x::S,check::AbstractCheckpoint{S},stopat) where S =
    checkindex(check) == stopat+1 ? nothing : EmptyCheckpoint{S}(stopat+1)
atcheckpoint(x,check) =
    error("Internal error: signal inconsistent with checkpoint")

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal,offset::Number) =
    sink!(result,x,sig,offset,atcheckpoint(x,offset,size(result,1)+offset))
function sink!(result,x,sig::IsSignal,offset,check)
    written = 0
    while !isnothing(check) && written < size(result,1)
        next = atcheckpoint(x,check,offset+size(result,1))
        isnothing(next) && break

        len = checkindex(next) - checkindex(check)
        @assert len > 0

        sink_helper!(result,offset,x,check,len)
        written += len
        check = next
    end
    @assert written == size(result,1)
    result
end

@noinline function sink_helper!(result,offset,x,check,len)
    @inbounds @simd for i in checkindex(check):(checkindex(check)+len-1)
        sampleat!(result,x,i-offset,i,check)
    end
end

@Base.propagate_inbounds function writesink!(result::AbstractArray,i,v)
    for ch in 1:length(v)
        result[i,ch] = v[ch]
    end
    v
end
