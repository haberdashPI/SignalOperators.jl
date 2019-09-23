struct NumberSignal{T,S,DB} <: AbstractSignal{T}
    val::T
    samplerate::S
end

NumberSignal(x::T,sr::Fs;dB=false) where {T,Fs} = NumberSignal{T,Fs,dB}(x,sr)
function Base.show(io::IO, ::MIME"text/plain", x::NumberSignal{<:Any,<:Any,true})
    show_number(io,x,uconvertrp(Units.dB, x.val))
end
function Base.show(io::IO, ::MIME"text/plain", x::NumberSignal{<:Any,<:Any,false})
    show_number(io,x,x.val)
end

function show_number(io,x,val)
    show(io, MIME("text/plain"), val)
    if !get(io,:compact,false) && !ismissing(x.samplerate)
        write(io," (")
        show(io, MIME("text/plain"), x.samplerate)
        write(io," Hz)")
    end
end

"""

## Numbers

Numbers can be treated as infinite length, constant signals of unknown
sample rate.

"""
signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
signal(val::Unitful.Gain,::Nothing,fs) = 
    NumberSignal(uconvertrp(NoUnits,val),inHz(Float64,fs),dB=true)

SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,InfiniteLength}()

nchannels(x::NumberSignal,::IsSignal) = 1
nsamples(x::NumberSignal,::IsSignal) = inflen
samplerate(x::NumberSignal,::IsSignal) = x.samplerate 

tosamplerate(x::NumberSignal,::IsSignal,::ComputedSignal,fs=missing;blocksize) = 
    NumberSignal(x.val,fs)

@Base.propagate_inbounds function sampleat!(result,x::NumberSignal,
    ::IsSignal,i::Number,j::Number,check)

    writesink!(result,i,x.val)
end
