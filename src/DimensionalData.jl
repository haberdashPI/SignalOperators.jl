using .DimensionalData

function signal(x::DimensionalData,::IsSignal,fs::Union{Missing,Number}=missing)
    if !isconsistent(fs,samplerate(x))
        error("Signal expected to have sample rate of $fs Hz.")
    else
        x
    end
end

function SignalTrait(x::Type{A}) where
        {A<:AbstractDimensionalArray{T,N,D}
    if N ∈
