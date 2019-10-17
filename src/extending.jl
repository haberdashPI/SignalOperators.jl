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

"""
    append(x,y,...)

Append a series of signals, one after the other.
"""
append(y) = x -> append(x,y)
"""
    prepend(x,y,...)

Prepend the series of signals: `prepend(xs...)` is equivalent to
`append(reverse(xs)...)`.

"""
prepend(x) = y -> append(x,y)
prepend(x,y,rest...) = prepend(reverse((x,y,rest...)...))

function append(xs...)
    if any(isinf ∘ nsamples,xs[1:end-1])
        error("Cannot append to the end of an infinite signal")
    end
    xs = uniform(xs,channels=true)

    El = promote_type(channel_eltype.(xs)...)
    xs = map(xs) do x
        if channel_eltype(x) != El
            toeltype(x,El)
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

struct AppendCheckpoint{Si,S,C} <: AbstractCheckpoint{Si}
    n::Int
    signal::S
    offset::Int
    child::C
end
checkindex(x::AppendCheckpoint) = x.n
function checkpoints(x::AppendSignals,offset,len)
    until = offset+len
    ns = nsamples.(x.signals[1:end-1])
    indices = collect(enumerate([1;cumsum(collect(ns)).+1]))

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

        Si,S = typeof(x),typeof(signal)
        [AppendCheckpoint{Si,S,typeof(c)}(checkindex(c)+index-1,
            signal,-index+1,c) for c in checks]
    end

    result
end
beforecheckpoint(x::S,check::AppendCheckpoint{S},len) where S <: AppendSignals =
    beforecheckpoint(check.signal,check.child,len)
aftercheckpoint(x::S,check::AppendCheckpoint{S},len) where S <: AppendSignals =
    aftercheckpoint(check.signal,check.child,len)

@Base.propagate_inbounds function sampleat!(result,x::AppendSignals,
    i,j,check)

    sampleat!(result,check.signal,i,j+check.offset,check.child)
end

Base.show(io::IO,::MIME"text/plain",x::AppendSignals) = pprint(io,x)
function PrettyPrinting.tile(x::AppendSignals)
    if length(x.signals) == 2
        child = signaltile(x.signals[1])
        operate = literal("append(") * signaltile(x.signals[2]) * literal(")") |
            literal("append(") / indent(4) * signaltile(x.signals[2]) / literal(")")
        tilepipe(child,operate)
    else
        list_layout(map(signaltile,x.signals),prefix="append",sep=",",sep_brk=",")
    end
end
signaltile(x::AppendSignals) = PrettyPrinting.tile(x)

################################################################################
# padding
struct PaddedSignal{S,T} <: WrappedSignal{S,T}
    signal::S
    pad::T
end
SignalTrait(x::Type{T}) where {S,T <: PaddedSignal{S}} =
    SignalTrait(x,SignalTrait(S))
SignalTrait(x::Type{<:PaddedSignal},::IsSignal{T,Fs}) where {T,Fs} =
    IsSignal{T,Fs,InfiniteLength}()
nsamples(x::PaddedSignal) = inflen
duration(x::PaddedSignal) = inflen
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,<:Number},c::ComputedSignal,fs;blocksize) =
    PaddedSignal(tosamplerate(x.signal,fs,blocksize=blocksize),x.pad)
tosamplerate(x::PaddedSignal,s::IsSignal{<:Any,Missing},__ignore__,fs;
    blocksize) = PaddedSignal(tosamplerate(x.signal,fs;blocksize=blocksize),x.pad)

"""

    pad(x,padding)

Create a signal that appends an infinite number of values, `padding`, to `x`.
The value `padding` can be a number or it can be a function of a type (e.g.
`zero`).

If the signal is already infinitely long (e.g. a previoulsy padded signal),
`pad` has no effect.

"""
pad(p) = x -> pad(x,p)
function pad(x,p)
    x = signal(x)
    isinf(nsamples(x)) ? x : PaddedSignal(x,p)
end

usepad(x::PaddedSignal) = usepad(x,SignalTrait(x))
usepad(x::PaddedSignal,s::IsSignal) = usepad(x,s,x.pad)
usepad(x::PaddedSignal,s::IsSignal{T},p::Number) where T =
    Fill(convert(T,p),nchannels(x.signal))
usepad(x::PaddedSignal,s::IsSignal{T},fn::Function) where T =
    Fill(fn(T),nchannels(x.signal))

childsignal(x::PaddedSignal) = x.signal

struct UsePad
end
const use_pad = UsePad()

struct PadCheckpoint{S,P,C} <: AbstractCheckpoint{S}
    n::Int
    pad::P
    child::C
end
checkindex(c::PadCheckpoint) = c.n
function checkpoints(x::PaddedSignal,offset,len)
    child_len = nsamples(childsignal(x))-offset
    child_checks = checkpoints(childsignal(x),offset, min(child_len,len))

    p = nothing
    child_checks = map(child_checks) do child
        p = checkindex(child) > offset+child_len ? usepad(x) : nothing
        S,P,C = typeof(x), typeof(p), typeof(child)
        PadCheckpoint{S,P,C}(checkindex(child),p,child)
    end
    S,P,C = typeof(x), typeof(p), Nothing
    if checkindex(child_checks[end]) != offset+len+1
        [child_checks; PadCheckpoint{S,P,C}(offset+len+1,p,nothing)]
    else
        child_checks
    end
end
beforecheckpoint(x::S,check::PadCheckpoint{S},len) where S <: PaddedSignal =
    beforecheckpoint(x.signal,check.child,len)
beforecheckpoint(x::S,check::PadCheckpoint{S,<:Any,Nothing},len) where
    {S <: PaddedSignal} = nothing
aftercheckpoint(x::S,check::PadCheckpoint{S},len) where S <: PaddedSignal =
    aftercheckpoint(x.signal,check.child,len)
aftercheckpoint(x::S,check::PadCheckpoint{S,<:Any,Nothing},len) where
    {S <: PaddedSignal} = nothing

@Base.propagate_inbounds function sampleat!(result,x::PaddedSignal,
    i,j,check::PadCheckpoint{<:Any,<:Nothing})

    sampleat!(result,x.signal,i,j,check.child)
end

@Base.propagate_inbounds function sampleat!(result,x::PaddedSignal,
    i,j,check::PadCheckpoint)

    writesink!(result,i,check.pad)
end

Base.show(io::IO,::MIME"text/plain",x::PaddedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::PaddedSignal)
    child = signaltile(x.signal)
    operate = literal(string("pad(",x.pad,")"))
    tilepipe(child,operate)
end
signaltile(x::PaddedSignal) = PrettyPrinting.tile(x)
