using .DimensionalData
using .DimensionalData: Time, @dim
@dim SigChannel "Signal Channel"
export SigChannel, Time

function signal(x::AbstractDimensionalArray,::IsSignal,
    fs::Union{Missing,Number}=missing)

    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
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

nsamples(x::AbstractDimensionalArray) = length(dims(x,Time))
nchannels(x::AbstractDimensionalArray) = prod(length,setdiff(dims(x),(dims(x,Time),)))

samplerate(x::AbstractDimensionalArray) =
    1/inseconds(Float64,step(dims(x,Time).val))

function nextblock(x::AbstractDimensionalArray,maxlen,skip,
    block=ArrayBlock([],0))

    offset = block.state + nsamples(block)
    if offset < nsamples(x)
        len = min(maxlen,nsamples(x)-offset)
        ArrayBlock(view(x,Time(offset .+ (1:len))),offset)
    end
end

function sink(x,::Type{<:DimensionalArray};kwds...)
    x,n = process_sink_params(x;kwds...)
    times = Time(range(0s,length=nsamples(x),step=1s/samplerate(x)))
    channels = SigChannel(1:nchannels(x))
    data = Array{channel_eltype(x)}(undef,length(times),length(channels))
    result = DimensionalArray(data,(times,channels))
    sink!(result,x)
end