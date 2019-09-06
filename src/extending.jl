export append, prepend, pad

################################################################################
# appending signals

struct AppendSignals{Si,All,T,L} <: WrappedSignal{Si,T}
    first::Si
    all::All
    len::L
end
SignalTrait(x::Type{T}) where T <: AppendSignals =
    SignalTrait(x,SignalTrait(T))
function SignalTrait(x::Type{<:AppendSignals{Si,Rst,T,L}},
        ::IsSignal{T,Fs}) where {Si,Rst,T,L,Fs}
    SignalTrait{T,Fs,L}()
end
childsignal(x::AppendSignals) = x.xs[1]
nsamples(x::AppendSignals,::IsSignal) = x.len

append(y) = x -> append(x,y)
prepend(x) = y -> append(x,y)
function append(xs...)
    if any(infsignal,xs[1:end-1])
        error("Cannot append to the end of an infinite signal")
    end
    xs = uniform(xs,channels=true) 
    El = promote_type(channel_eltype.(xs)...)
    xs = mapsignal.(x -> convert(El,x),xs)
    len = infsignal(xs[end]) ? nothing : sum(nsamples,xs)
    AppendSignals(xs[1], xs, len, samplerate(xs))
end
tosamplerate(x::AppendSignals,s::IsSignal,c::ComputedSignal,fs) = 
    append(tosamplerate(x.first,fs),tosamplerate.(x.rest,fs)...)

struct AppendCheckpoint{C} <: AbstractCheckpoint
    n::Int
    sig_index::Int
    offset::Int
    child::C
end
checkindex(x::AppendCheckpoint) = x.n
function checkpoints(x::AppendSignals,offset,len)
    until = offset+len
    indices = collect(enumerate([1;cumsum(nsamples.(x.all[1:end-1])).+1]))

    result = mapreduce(vcat,x.all,indices) do (signal,(sig_index,index))
        checks = checkpoints(signal,offset,nsamples(x.all))
        [AppendCheckpoint(checkindex(c)+index-1,sig_index,-index+1,c) 
            for c in checks]
    end

    # cut out any checkpoints not in the appropriate range
    start = findlast(@λ(offset > checkindex(_)),result)
    start = isnothing(start) ? 1 : start
    stop = findlast(@λ(checkindex(_) < until),indices)
    stop = isnothing(stop) ? length(indices) : stop

    # if the first checkout has a negative index, revise it to have
    # a positive index
    result = result[start:stop]
    result[1] = AppendCheckpoint(1,result[1].sig_index,
        result[1].offset + (result[1].n - 1),result[1].child)

    result
end
sampleat!(result,x,sig,i,j,check) =
    sampleat!(result,x.all[check.sig_index],i,j+check.offset,check.child)

################################################################################
# padding
struct PaddedSignal{S,T} <: WrappedSignal{S,T}
    x::S
    pad::T
end
SignalTrait(x::Type{T}) where T <: PaddedSignal = SignalTrait(x,SignalTrait(T))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs}) where {T,Fs} =
    SignalTrait{T,Fs,Nothing}()
nsamples(x::PaddedSignal) = nothing
tosamplerate(x::PaddedSignal,s::IsSignal,c::ComputedSignal,fs) =
    PaddedSignal(tosamplerate(x.x,fs),x.pad)

pad(p) = x -> pad(x,p)
function pad(x,p) 
    x = signal(x)
    infsignal(x) ? x : PaddedSignal(x,p)
end

usepad(x::PaddedSignal) = usepad(x,SignalTrait(x))
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{1,<:Any}}) = (usepad(x,s,x.pad),)
function usepad(x::PaddedSignal,s::IsSignal{NTuple{2,<:Any}})
    v = usepad(x,s,x.pad)
    (v,v)
end
function usepad(x::PaddedSignal,s::IsSignal{<:NTuple{N,<:Any}}) where N
    v = usepad(x,s,x.pad)
    tuple((v for _ in 1:N)...)
end

usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},p::Number) where T = 
    convert(T,p)
usepad(x::PaddedSignal,s::IsSignal{<:NTuple{<:Any,T}},fn::Function) where T = 
    fn(T)

childsignal(x::PaddedSignal) = x.x

struct UsePad
end
const use_pad = UsePad()

struct PadCheckpoint{C}
    n::Int
    usepad::Bool
    child::C
end
checkindex(c::PadCheckpoint) = c.n
function checkpoints(x::PaddedSignal,offset,len)
    child_len = nsamples(childsignal(x))-offset
    child_checks = checkpoints(childsignal(x),offset, min(child_len,len))
    
    usepad = false
    map(child_checks) do child
        if checkindex(child) == child_len
            usepad = true
        end
        PadCheckpoint(checkindex(child),usepad,child)
    end
end
function sinkchunk!(result,off,x::PaddedSignal,::IsSignal,check,until)
    if !check.usepad
        sinkchunk!(result,off,x.x,SignalTrait(x.x),check,until)
    else
        p = usepad(x)
        @inbounds @simd for i in checkindex(check):last
            writesink(result,i-off,p)
        end
    end
end