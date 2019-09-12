export append, prepend, pad

################################################################################
# appending signals

struct AppendSignals{Si,Sis,T,L} <: WrappedSignal{Si,T}
    signals::Sis
    len::L
end
SignalTrait(x::Type{T}) where {Si,T <: AppendSignals{Si}} =
    SignalTrait(x,SignalTrait(Si))
function SignalTrait(x::Type{<:AppendSignals{Si,Rst,T,L}},
        ::IsSignal{T,Fs}) where {Si,Rst,T,L,Fs}
    IsSignal{T,Fs,L}()
end
childsignal(x::AppendSignals) = x.signals[1]
nsamples(x::AppendSignals,::IsSignal) = x.len
duration(x::AppendSignals) = sum(duration.(x.signals))

append(y) = x -> append(x,y)
prepend(x) = y -> append(x,y)
function append(xs...)
    if any(isinf ∘ nsamples,xs[1:end-1])
        error("Cannot append to the end of an infinite signal")
    end
    xs = uniform(xs,channels=true) 

    El = promote_type(channel_eltype.(xs)...)
    xs = map(xs) do x
        if channel_eltype(x) != El
            mapsignal(@λ(convert(El,_)),x)
        else
            x
        end
    end

    len = sum(nsamples,xs)
    AppendSignals{typeof(xs[1]),typeof(xs),El,typeof(len)}(xs, len)
end
tosamplerate(x::AppendSignals,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) = 
    append(tosamplerate.(x.signals,fs;blocksize=blocksize)...)
tosamplerate(x::AppendSignals,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = append(tosamplerate.(x.signals,fs;blocksize=blocksize)...)

struct AppendCheckpoint{C} <: AbstractCheckpoint
    n::Int
    sig_index::Int
    offset::Int
    child::C
end
checkindex(x::AppendCheckpoint) = x.n
function checkpoints(x::AppendSignals,offset,len)
    until = offset+len
    indices = 
        collect(enumerate([1;cumsum(collect(nsamples.(x.signals[1:end-1]))).+1]))

    written = 0
    droplast_unless(x,cond) = cond ? x : x[1:end-1]
    # NOTE: zip is for compatibility with 1.0 (mapreudce only supports multiple
    # iterators in Julia 1.1+)
    result = mapreduce(vcat,zip(x.signals,indices)) do (signal,(sig_index,index))
        checks = if index-offset > len
            []
        elseif index-offset > 0
            local_len = min(len-written,nsamples(signal))
            written += local_len
            droplast_unless(checkpoints(signal,0,local_len),
                sig_index == length(x.signals))
        elseif index + nsamples(signal) - offset > 0
            sigoffset = -(index-offset)+1
            local_len = min(nsamples(signal)-sigoffset+1,len-written)
            written += local_len
            droplast_unless(checkpoints(signal,sigoffset,local_len),
                sig_index == length(x.signals))
        else
            []
        end

        [AppendCheckpoint(checkindex(c)+index-1,sig_index,-index+1,c) 
         for c in checks]
    end

    result
end
beforecheckpoint(x::AppendCheckpoint,check,len) = 
    beforecheckpoint(x.signal,check.child,len)
aftercheckpoint(x::AppendCheckpoint,check,len) = 
    aftercheckpoint(x.signal,check.child,len)
function sampleat!(result,x::AppendSignals,sig::IsSignal,i,j,check)
    sampleat!(result,x.signals[check.sig_index],sig,i,j+check.offset,check.child)
end

################################################################################
# padding
struct PaddedSignal{S,T} <: WrappedSignal{S,T}
    x::S
    pad::T
end
SignalTrait(x::Type{T}) where {S,T <: PaddedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs}) where {T,Fs} =
    IsSignal{T,Fs,InfiniteLength}()
nsamples(x::PaddedSignal) = inflen
duration(x::PaddedSignal) = inflen
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    PaddedSignal(tosamplerate(x.x,fs,blocksize=blocksize),x.pad)
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = PaddedSignal(tosamplerate(x.x,fs;blocksize=blocksize),x.pad)

pad(p) = x -> pad(x,p)
function pad(x,p) 
    x = signal(x)
    isinf(nsamples(x)) ? x : PaddedSignal(x,p)
end

usepad(x::PaddedSignal) = usepad(x,SignalTrait(x))
usepad(x::PaddedSignal,s::IsSignal) = usepad(x,s,x.pad)
usepad(x::PaddedSignal,s::IsSignal{T},p::Number) where T = convert(T,p)
usepad(x::PaddedSignal,s::IsSignal{T},fn::Function) where T = fn(T)

childsignal(x::PaddedSignal) = x.x

struct UsePad
end
const use_pad = UsePad()

struct PadCheckpoint{P,C} <: AbstractCheckpoint
    n::Int
    child::C
end
checkindex(c::PadCheckpoint) = c.n
function checkpoints(x::PaddedSignal,offset,len)
    child_len = nsamples(childsignal(x))
    child_checks = checkpoints(childsignal(x),offset, min(child_len,len))
    
    dopad = false
    oldchecks = map(child_checks) do child
        dopad = checkindex(child) > child_len
        PadCheckpoint{dopad,typeof(child)}(checkindex(child),child)
    end
    [oldchecks; PadCheckpoint{dopad,Nothing}(offset+len+1,nothing)]
end
beforecheckpoint(x::PadCheckpoint,check,len) = 
    beforecheckpoint(x.child,check.child,len)
aftercheckpoint(x::PadCheckpoint,check,len) = 
    aftercheckpoint(x.child,check.child,len)

function sampleat!(result,x::PaddedSignal,::IsSignal,i,j,
    check::PadCheckpoint{false})

    sampleat!(result,x.x,SignalTrait(x.x),i,j,check.child)
end
function sampleat!(result,x::PaddedSignal,::IsSignal,i,j,
    check::PadCheckpoint{true})

    writesink(result,i,usepad(x))
end