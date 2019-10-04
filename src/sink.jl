
"""
    sink([signal],[to=AxisArray];duration,samplerate)

Creates a given type of object (`to`) from a signal. By default it is an
`AxisArray` with time as the rows and channels as the columns. If a filename
is specified for `to`, the signal is written to the given file. If given a
type (e.g. `Array`) the signal is written to a value of that type. The sample rate does
not need to be specified, it will use either the sample rate of `signal` or a
default sample rate (which raises a warning). 

You can specify a duration or sample rate for the signal when calling sink if it
has yet to be defined.

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
        error("Cannot store infinite signal. Specify a duration when ",
            "calling `sink`.")
    end

    sink(x,SignalTrait(T),insamples(Int,maybeseconds(duration),
        SignalOperators.samplerate(x)),A)
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

abstract type AbstractCheckpoint
end
struct EmptyCheckpoint <: AbstractCheckpoint
    n::Int
end
checkindex(x::EmptyCheckpoint) = x.n

checkpoints(x,offset,len) = 
    [EmptyCheckpoint(offset+1),EmptyCheckpoint(offset+len+1)]
beforecheckpoint(x,check,len) = nothing
aftercheckpoint(x,check,len) = nothing

# sampleat!(result,x,sig,i,j,check) = sampleat!(result,x,sig,i,j)

fold(x) = zip(x,Iterators.drop(x,1))
sink!(result,x,sig::IsSignal,offset::Number) = 
    sink!(result,x,sig,checkpoints(x,offset,size(result,1)))
function sink!(result,x,sig::IsSignal,checks::AbstractArray)
    n = 1-checkindex(checks[1])
    for (check,next) in fold(checks)
        len = checkindex(next) - checkindex(check)
        beforecheckpoint(x,check,len)
        sink_helper!(result,n,x,check,len)
        aftercheckpoint(x,check,len)
    end
    result
end

@noinline function sink_helper!(result,n,x,check,len)
    if len > 0
        @inbounds @simd for i in checkindex(check):(checkindex(check)+len-1)
            sampleat!(result,x,n+i,i,check)
        end
    end
end

struct BroadcastNum{T}
    x::T
end

Base.getindex(x::BroadcastNum,ixs::Int...) = x.x
@Base.propagate_inbounds function writesink!(result::AbstractArray,i,
    v::BroadcastNum)

    for ch in 1:size(result,2)
        result[i,ch] = v.x
    end
    v
end

@Base.propagate_inbounds function writesink!(result::AbstractArray,i,v)
    for ch in 1:length(v)
        result[i,ch] = v[ch]
    end
    v
end
