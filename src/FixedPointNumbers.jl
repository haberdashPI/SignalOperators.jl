using .FixedPointNumbers

function Pad(x,p::typeof(one))
    if isknowninf(nframes(x))
        x
    elseif sampletype(x) <: Fixed
        x |> ToEltype(float(sampletype(x))) |> Pad(p)
    else
        PaddedSignal(x,p)
    end
end