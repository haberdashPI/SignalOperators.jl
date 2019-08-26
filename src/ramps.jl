

function rampup_fn(len)
    time = inseconds(len)
    x -> x ≤ time : sinpi(0.5x/time) : 1.0
end

rampup(len) = x -> rampup(x,len)
function rampup(x,len)
    signal(rampup_fn(len),samplerate(x)) |> amplify(x)
end

function rampdown_fn(x,len)
    time = inseconds(len)
    x -> x < duration(x) - time : 1.0 : sinpi(0.5 + 0.5x/time)
end

rampdown(len) = x -> rampdown(x,len)
function rampdown(x,len)
    signal(rampdown_fn(len),samplerate(x)) |> amplify(x)
end

ramp(len) = x -> ramp(x,len)
function ramp(x,len)
    x |> rampup(len) |> rampdown(len)
end

fadeto(y,len) = x -> fadeto(x,y,len)
function fadeto(x,y,len)
    silence = signal(zero,x) |> until(nsamples(x) - inframesof(len,x))
    y = y |> rampup(len) |> prepend(silence)
    x |> rampdown(len) |> mix(y)
end
