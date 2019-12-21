using .DimensionalData
using .DimensionalData: Time, @dim
@dim SigChannel "Signal Channel"
export SigChannel, Time

init_array_backend!(DimensionalArray)
function arraysignal(x,::Type{<:DimensionalArray},fs)
    if ndims(x) == 1
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        DimensionalArray(x,(Time(times),))
    elseif ndims(x) == 2
        times = range(0s,length=size(x,1),step=float(s/inHz(fs)))
        channels = 1:size(x,2)
        DimensionalArray(x,(Time(times),SigChannel(channels)))
    else
        errordim()
    end
end

function signal(x::AbstractDimensionalArray,::IsSignal,
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

function initsink(x,::Type{<:DimensionalArray},len)
    times = Time(range(0s,length=len,step=1s/framerate(x)))
    channels = SigChannel(1:nchannels(x))
    DimensionalArray(initsink(x,Array,len)[1],(times,channels))
end
