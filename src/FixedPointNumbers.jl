using .FixedPointNumbers

function pad(x,p::typeof(one))
    if isinf(nsamples(x))
        x
    elseif channel_eltype(x) <: Fixed
        x |> toeltype(float(channel_eltype(x))) |> pad(p)
    else
        PaddedSignal(x,p)
    end
end