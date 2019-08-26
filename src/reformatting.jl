

################################################################################
# resampling

tosamplerate(x,fs) = tosamplerate(x,SignalTrait(x),fs)
tosamplerate(x,::Nothing,fs) = 
    error("Don't know how to set sample rate of non signal: $x")
tosamplerate(x,::IsSignal,fs) = format(x,fs,nchannels(x))

tochannels(x,ch) = tochannels(x,SignalTrait(x),fs)
tosamplerate(x,::Nothing,fs) = 
    error("Don't know how to set number of channgles of non signal: $x")
tochannels(x,::IsSignal,ch) = format(x,samplerate(x),ch)

function format(x,fs,ch)
    data = asarray(x)
    ratio = rationalize(fs/samplerate(x))
    
    if ratio == 1
        if ch == size(data,2)
            data
        elseif ch == 1
            sum(data,dims=2)
        elseif size(data,2) == 1
            reduce(hcat,(data for _ in 1:ch))
        else
        error("No rule to convert signal with $(size(data,2)) channels to",
              " a signal with $ch channels.")
        end
    elseif ch == size(data,2)
        mapreduce(hcat,1:size(data,2)) do c
            DSP.resample(data[:,c],ratio)
        end
    elseif ch == 1
        c = 1
        first = DSP.resample(data[:,c],ratio)
        for c in 2:size(data,2)
            first .+= DSP.resample(data[:,c],ratio)
        end
    elseif size(data,2) == 1
        first = DSP.resample(data,ratio)
        reduce(hcat,(first for _ in 1:size(data,2)))
    else
        error("No rule to convert signal with $(size(data,2)) channels to",
              " a signal with $ch channels.")
    end
end

# TODO: support resampling of infinite length signals

# function tosamplerate(x,::IsSignal(x),fs;block_size=4096)
#     ratio = rationalize(fs/samplerate(x))
#     coefs = resample_filter(ratio)
#     filters = [FIRFilter(coefs, ratio) for _ in 1:nchannels(x)]
#     sig = samples(x)
#     block = zero_helper(eltype(x),min(block_size,length(sig)))
    
# function resmaple_block(block,sig,::HasLength)
#     result = iterate(sig)
#     count = 0
#     for 1:min(length(sig),block)
#     filt!()
# end

any_samplerate(x) = any_samplerate(x,SignalTrait(x))
any_samplerate(x,s::SignalTrait) = s.samplerate
any_samplerate(x,::Nothing) = 0.0

any_nchannels(x,fs) = any_nchannels(x,SignalTrait(x),fs)
any_nchannels(x,s::SignalTrait,fs) = nchannels(x)
any_nchannels(x,::Nothing,fs) = any_nchannels(signal(x,fs))

maybe_format(x,fs,ch=any_nchannels(x)) = maybe_format(x,SignalTrait(x),fs,ch)
maybe_format(x,::Nothing,fs,ch) = maybe_format(signal(x,fs),fs,ch)
function maybe_format(x,s::SignalTrait,fs,ch) 
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
