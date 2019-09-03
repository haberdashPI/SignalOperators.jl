using DSP: FIRFilter, resample_filter
export tosamplerate, tochannels, format, uniform

tosamplerate(fs) = x -> tosamplerate(x,fs)
tosamplerate(x,fs) = tosamplerate(x,SignalTrait(x),EvalTrait(x),fs)
tosamplerate(x,::Nothing,ev,fs) = nosignal(x)

function tosamplerate(x,s::IsSignal{T},::DataSignal,fs) where T
    # copied and modified from DSP's `resample`
    ratio = rationalize(inHz(fs)/samplerate(x))
    if ratio == 1
        x
    else
        h = resample_filter(ratio)
        self = FIRFilter(h, ratio)
        τ = timedelay(self)
        setphase!(self, τ)

        x = if !infsignal(x)
            outlen = ceil(Int, nsamples(x)*ratio)
            inlen = inputlength(self, outlen)
            pad(x,zero) |> until(inlen*frames)
        else
            x
        end

        filtersignal(x,IsSignal{T}(inHz(fs)),self)
    end
end

tochannels(ch) = x -> tochannels(x,ch)
tochannels(x,ch) = tochannels(x,SignalTrait(x),ch)
tochannels(x,::Nothing,ch) = 
    error("Don't know how to set number of channgles of non signal: $x")
function tochannels(x,::IsSignal,ch) 
    if ch == nchannels(x)
        x
    elseif ch == 1
        mix((channel(x,ch) for ch in 1:nchannels(x))...)
    elseif nchannels(x) == 1
        mapsignal(x -> tuple((x[1] for _ in 1:ch)...),x,across_channels=true)
    else
        error("No rule to convert signal with $(nchannels(x)) channels to",
            " a signal with $ch channels.")
    end
end

function format(x,fs,ch)
    if ch > 1 && nchannels(x) == 0
        tosamplerate(x,fs) |> tochannels(ch)
    else
        tochannels(x,ch) |> tosamplerate(fs)
    end
end

function uniform(xs;channels=false)
    xs = signal.(xs)
    samplerate = maximum(skipmissing(samplerate.(xs)))
    if !channels
        format.(xs,samplerate)
    else
        ch = maximum(skipmissing(nchannels.(xs)))
        format.(xs,samplerate,ch)
    end
end
