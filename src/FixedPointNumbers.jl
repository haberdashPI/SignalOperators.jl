using .FixedPointNumbers

function Pad(x,p::typeof(one))
    if isinf(nframes(x))
        x
    elseif channel_eltype(x) <: Fixed
        x |> ToEltype(float(channel_eltype(x))) |> Pad(p)
    else
        PaddedSignal(x,p)
    end
end