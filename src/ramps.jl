
export rampup, rampdown, ramp, fadeto

function rampup_fn(x,len,fun)
    time = inseconds(len,samplerate(x))
    x -> x ≤ time ? fun(x/time) : 1.0
end

sinramp(x) = sinpi(0.5x)
rampup(fun::Function) = rampup(10ms,fun)
rampup(len::Number=10ms,fun::Function=sinramp) = x -> rampup(x,len,fun)
function rampup(x,len::Number=10ms,fun::Function=sinramp)
    signal(rampup_fn(len,fun),samplerate(x)) |> amplify(x)
end

function rampdown_fn(x,len,fun)
    time = inseconds(len,samplerate(x))
    ramp_start = duration(x) - time
    x -> x < ramp_start ? 1.0 : fun(1.0 - (x-ramp_start)/time)
end

rampdown(fun::Function) = rampdown(10ms,fun)
rampdown(len::Number=10ms,fun::Function=sinramp) = x -> rampdown(x,len,fun)
function rampdown(x,len::Number=10ms,fun::Function=sinramp)
    signal(rampdown_fn(len),samplerate(x)) |> amplify(x)
end

ramp(fun::Function) = ramp(10ms,fun)
ramp(len::Number=10ms,fun::Function=sinramp) = x -> ramp(x,len,fun)
function ramp(x,len::Number,fun::Function)
    x |> rampup(len,fun) |> rampdown(len,fun)
end

fadeto(y,fun::Function) = fadeto(y,10ms,fun)
fadeto(y,len::Number=10ms,fun::Function=sinramp) = x -> fadeto(x,y,len,fun)
function fadeto(x,y,len::Number=10ms,fun::Function=sinramp)
    n = inframes(Int,len,samplerate(x))
    silence = signal(zero,x) |> until(nsamples(x) - n)
    y = y |> rampup(len,fun) |> prepend(silence)
    x |> rampdown(len,fun) |> mix(y)
end
