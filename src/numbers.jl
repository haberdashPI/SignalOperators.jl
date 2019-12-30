struct NumberSignal{T,S,DB} <: AbstractSignal{T}
    val::T
    framerate::S
end

NumberSignal(x::T,sr::Fs;dB=false) where {T,Fs} = NumberSignal{T,Fs,dB}(x,sr)
function Base.show(io::IO, ::MIME"text/plain", x::NumberSignal{<:Any,<:Any,true})
    show(io,MIME("text/plain"), uconvertrp(Units.dB, x.val))
    show_fs(io,x)
end
function Base.show(io::IO, ::MIME"text/plain", x::NumberSignal{<:Any,<:Any,false})
    show(io, MIME("text/plain"), x.val)
    show_fs(io,x)
end

"""

## Numbers

Numbers can be treated as infinite length, constant signals of unknown
frame rate.

"""
Signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
Signal(val::Unitful.Gain{<:Any,<:Any,T},::Nothing,fs) where T =
    NumberSignal(float(T)(uconvertrp(NoUnits,val)),inHz(Float64,fs),dB=true)

SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,InfiniteLength}()

nchannels(x::NumberSignal) = 1
nframes(x::NumberSignal) = inflen
framerate(x::NumberSignal) = x.framerate

ToFramerate(x::NumberSignal{<:Any,<:Any,DB},::IsSignal,::ComputedSignal,
    fs=missing;blocksize) where DB = NumberSignal(x.val,fs,dB=DB)

struct NumberBlock
    len::Int
end
nextblock(x::NumberSignal,len,skip,block::NumberBlock=NumberBlock(0)) = NumberBlock(len)
nframes(block::NumberBlock) = block.len
frame(x,block::NumberBlock,i) = x.val