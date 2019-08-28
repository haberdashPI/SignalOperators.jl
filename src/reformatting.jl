using DSP: FIRFilter, resample_filter
export tosamplerate, tochannels, format, uniform

tosamplerate(x,fs) = tosamplerate(x,SignalTrait(x),fs)
tosamplerate(x,::Nothing,fs) = 
    error("Don't know how to set sample rate of non signal: $x")

function tosamplerate(x,s::IsSignal{N},fs) where N
    # copieded and modified from DSP's `resample`
    ratio = rationalize(fs/samplerate(x))
    if ratio == 1
        x
    else
        h = resample_filter(rate)
        self = FIRFilter(h, ratio)
        τ = timedelay(self)
        setphase!(self, τ)

        x = if !infsignal(x)
            outlen = ceil(Int, nsamples(x)*rate)
            inlen = inputlength(h, outlen)
            pad(x,zero) |> until(inlen*frames)
        else
            x
        end

        filtersignal(x,IsSignal{N}(fs),self)
    end
end

tochannels(x,ch) = tochannels(x,SignalTrait(x),ch)
tochannels(x,::Nothing,ch) = 
    error("Don't know how to set number of channgles of non signal: $x")
function tochannels(x,::IsSignal,ch) 
    if ch == nchannels(x)
        x
    elseif ch == 1
        mix((channel(x,ch) for ch in 1:nchannels(x))...)
    elseif nchannels(x) == 1
        signalop(x -> tuple((x for _ in 1:ch)...),x)
    else
        error("No rule to convert signal with $(size(data,2)) channels to",
            " a signal with $ch channels.")
    end
end

function format(x,fs,ch)
    if ch > 1 && nchannels(x) == 0
        tosamplerate(x,fs) |> tochannels(x,ch)
    else
        tochannels(x,ch) |> tosamplerate(x,fs)
    end
end

any_samplerate(x) = any_samplerate(x,SignalTrait(x))
any_samplerate(x,s::IsSignal) = s.samplerate
any_samplerate(x,::Nothing) = 0.0

any_nchannels(x,fs) = any_nchannels(x,SignalTrait(x),fs)
any_nchannels(x,s::IsSignal,fs) = nchannels(x)
any_nchannels(x,::Nothing,fs) = any_nchannels(signal(x,fs))

maybe_format(x,fs,ch=any_nchannels(x)) = maybe_format(x,SignalTrait(x),fs,ch)
maybe_format(x,::Nothing,fs,ch) = maybe_format(signal(x,fs),fs,ch)
function maybe_format(x,s::IsSignal,fs,ch) 
    format(x,fs,ch)
end

function uniform(xs;channels=false)
    samplerate = maximum(any_samplerate.(xs))
    if !channels
        maybe_format.(xs,samplerate)
    else
        ch = maximum(any_nchannels.(xs,samplerate))
        maybe_format.(xs,samplerate,ch)
    end
end
