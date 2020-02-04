struct NumberSignal{T,S,DB} <: AbstractSignal{T}
    val::T
    framerate::S
end
struct NumberExtended <: Infinite
end
const numextend = NumberExtended()
nframes_helper(x::NumberSignal) = numextend
cleanextend(x::NumberExtended) = inflen

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

### Example

```julia
rand(10,2) |> Amplify(20dB) |> nframes == 10

```

!!! note

    The length of numbers are treated specially when passed to
    [`OperateOn`](@ref): if there are other types of signal passed as input,
    the number signals are considered to be as long as the longest signal.

    ```julia
    nframes(Mix(1,2)) == inflen
    nframes(Mix(1,rand(10,2))) == 10
    ```

"""
Signal(val::Number,::Nothing,fs) = NumberSignal(val,inHz(Float64,fs))
Signal(val::Unitful.Gain{<:Any,<:Any,T},::Nothing,fs) where T =
    NumberSignal(float(T)(uconvertrp(NoUnits,val)),inHz(Float64,fs),dB=true)

SignalTrait(::Type{<:NumberSignal{T,S}}) where {T,S} = IsSignal{T,S,InfiniteLength}()

nchannels(x::NumberSignal) = 1
framerate(x::NumberSignal) = x.framerate

ToFramerate(x::NumberSignal{<:Any,<:Any,DB},::IsSignal,::ComputedSignal,
    fs=missing;blocksize) where DB = NumberSignal(x.val,fs,dB=DB)

struct NumberBlock
    len::Int
end
nextblock(x::NumberSignal,len,skip,block::NumberBlock=NumberBlock(0)) = NumberBlock(len)
nframes(block::NumberBlock) = block.len
frame(x,block::NumberBlock,i) = x.val