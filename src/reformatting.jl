using DSP: FIRFilter, resample_filter
export tosamplerate, tochannels, format, uniform

tosamplerate(fs;blocksize=default_blocksize) = 
    x -> tosamplerate(x,fs;blocksize=blocksize)
tosamplerate(x,fs;blocksize=default_blocksize) = 
    ismissing(fs) && ismissing(samplerate(x)) ? x :
        coalesce(inHz(fs) == samplerate(x),false) ? x :
        tosamplerate(x,SignalTrait(x),EvalTrait(x),fs;blocksize=blocksize)
tosamplerate(x,::Nothing,ev,fs;kwds...) = nosignal(x)

tosamplerate(x,::IsSignal,::DataSignal,::Missing;kwds...) = x
tosamplerate(x,::IsSignal,::ComputedSignal,::Missing;kwds...) = x

function tosamplerate(x,s::IsSignal{T},::DataSignal,fs;blocksize) where T
    if ismissing(samplerate(x))
        signal(x,fs)
    end

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

        filtersignal(x,s,_ -> self;blocksize=blocksize,newfs=inHz(fs))
    end
end

tochannels(ch) = x -> tochannels(x,ch)
tochannels(x,ch) = tochannels(x,SignalTrait(x),ch)
tochannels(x,::Nothing,ch) = tochannels(signal(x),ch)
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

function format(x,fs,ch=nchannels(x))
    if ch > 1 && nchannels(x) == 0
        tosamplerate(x,fs) |> tochannels(ch)
    else
        tochannels(x,ch) |> tosamplerate(fs)
    end
end

function uniform(xs;channels=false)
    xs = signal.(xs)
    samplerate = maximum(skipmissing(SignalOperators.samplerate.(xs)))
    if !channels
        format.(xs,samplerate)
    else
        ch = maximum(skipmissing(nchannels.(xs)))
        format.(xs,samplerate,ch)
    end
end
