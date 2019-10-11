
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

checkpoints(x::S,offset,len) where S = 
    [EmptyCheckpoint{S}(offset+1),EmptyCheckpoint{S}(offset+len+1)]
beforecheckpoint(x::S,check::AbstractCheckpoint{S},len) where S = nothing
beforecheckpoint(x,check,len) = 
    error("Internal error: signal inconsistent with checkpoint")
aftercheckpoint(x::S,check::AbstractCheckpoint{S},len) where S = nothing
aftercheckpoint(x,check,len) = 
    error("Internal error: signal inconsistent with checkpoint")

# sampleat!(result,x,sig,i,j,check) = sampleat!(result,x,sig,i,j)

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal,offset::Number) = 
    sink!(result,x,sig,checkpoints(x,offset,size(result,1)))
function sink!(result,x,sig::IsSignal,checks::AbstractArray)
    n = 1-checkindex(checks[1])
    afters = sizehint!([],length(checks))
    for (check,next) in fold(checks)
        len = checkindex(next) - checkindex(check)
        beforecheckpoint(x,check,len)
        if len > 0 
            sink_helper!(result,n,x,check,len)
            aftercheckpoint(x,check,len)
            for after in afters; aftercheckpoint(x,after,len); end
            empty!(afters)
        else
            push!(afters,check)
        end
    end
    result
end

@noinline function sink_helper!(result,n,x,check,len)
    @inbounds @simd for i in checkindex(check):(checkindex(check)+len-1)
        sampleat!(result,x,n+i,i,check)
    end
end

@Base.propagate_inbounds function writesink!(result::AbstractArray,i,v)
    for ch in 1:length(v)
        result[i,ch] = v[ch]
    end
    v
end
