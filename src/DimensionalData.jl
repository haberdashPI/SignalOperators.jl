using .DimensionalData
using .DimensionalData: Time, @dim
@dim SigChannel "Signal Channel"
export SigChannel, Time

function Signal(x::AbstractDimensionalArray,::IsSignal,
    fs::Union{Missing,Number}=missing)

    if !isconsistent(fs,framerate(x))
        error("Signal expected to have frame rate of $fs Hz.")
    else
        x
    end
end

hastime(::Type{T}) where T <: Tuple = any(@λ(_ <: Time),T.types)
function SignalTrait(::Type{<:AbstractDimensionalArray{T,N,Dim}}) where {T,N,Dim}
    if hastime(Dim)
        IsSignal{T,Float64,Int}()
    else
        error("Dimensional array must have a `Time` dimension.")
    end
end

nframes(x::AbstractDimensionalArray) = length(dims(x,Time))
nchannels(x::AbstractDimensionalArray) =
    prod(length,setdiff(dims(x),(dims(x,Time),)))

framerate(x::AbstractDimensionalArray) =
    1/inseconds(Float64,step(dims(x,Time).val))

timeslice(x::AbstractDimensionalArray,indices) = view(x,Time(indices))

function initsink(x,::Type{<:DimensionalArray},
    data=Array{channel_eltype(x)}(undef,nframes(x),nchannels(x)))

    times = Time(range(0s,length=nframes(x),step=1s/framerate(x)))
    channels = SigChannel(1:nchannels(x))
    DimensionalArray(initsink(x,Array,data),(times,channels))
end
DimensionalData.DimensionalArray(x::AbstractSignal) = sink(x,DimensionalArray)