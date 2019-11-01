export append, prepend, pad, cycle, mirror, lastsample

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
child(x::AppendSignals) = x.signals[1]
nsamples(x::AppendSignals) = x.len
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
    signal::S
    offset::Int
    child::C
    k::Int
end
checkindex(x::AppendCheckpoint) = checkindex(x.child)+x.offset
child(x::AppendCheckpoint) = x.child

atcheckpoint(x::AppendSignals,offset::Number,stopat) =
    append_checkpoint(x,nothing,offset+1,stopat,1,0)

atcheckpoint(x::S,check::AppendCheckpoint{S},stopat) where S <: AppendSignals =
    append_checkpoint(x,check,checkindex(check),stopat,check.k,
        check.offset)

function append_checkpoint(x,check,startat,stopat,start_k,offset)
    childcheck = nothing
    childsig = x.signals[1]
    k = start_k
    K = length(x.signals)
    keepme(k,sig,check) =
        !isnothing(check) && (k == K || checkindex(check) ≤ nsamples(sig))
    while isnothing(childcheck) && k ≤ length(x.signals)
        childsig = x.signals[k]
        child_range = (1:nsamples(childsig)) .+ offset
        if !isempty((startat:stopat) ∩ child_range)
            child_stopat = min(stopat - offset,nsamples(childsig))
            if isnothing(check) || k != start_k
                child_offset = max(0,startat - offset - 1)
                childcheck = atcheckpoint(childsig,child_offset,child_stopat)
                keepme(k,childsig,childcheck) || (childcheck = nothing)
            else
                childcheck = atcheckpoint(childsig,child(check),child_stopat)
                keepme(k,childsig,childcheck) || (childcheck = nothing)
            end
        end
        if isnothing(childcheck)
            offset += nsamples(childsig)
            k += 1
        end
    end

    if !isnothing(childcheck)
        Si,S = typeof(x),typeof(childsig)
        AppendCheckpoint{Si,S,typeof(childcheck)}(childsig,offset,childcheck,k)
    end
end

@Base.propagate_inbounds function sampleat!(result,x::AppendSignals,
    i,j,check)

    sampleat!(result,check.signal,i,j-check.offset,check.child)
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
The value `padding` can be:

- a number
- a tuple or vector
- a type function: a one argument function of the `channel_eltype` of `x`
- a value function: a one argument function of the signal `x` for which
    `SignalOperators.valuefunction(padding) == true`.
- an indexing function: a three argument function following the same type
  signature as `getindex` for two dimensional arrays.

If the signal is already infinitely long (e.g. a previoulsy padded signal),
`pad` has no effect.

If `padding` is a number it is used as the value for all samples and channels
past the end of `x`.

If `padding` is a tuple or vector it is the value for all samples past the end
of `x`.

If `padding` is a type function it is passed the [`channel_eltype`](@ref) of
the signal and the resulting value is used as the value for all samples past
the end of `x`. Examples include `zero` and `one`

If `padding` is a value function it is passed `x` just before padding during
`sink` begins and it should return a tuple of `channel_eltype(x)` values.
This value is repeated for the remaining samples. It is generally only useful
when x is an AbstractArray.

If `padding` is an indexing function (it accepts 3 arguments) it will be used
to retrieve samples from the signal `x` assuming it conforms to the
`AbstractArray` interface, with the first index being samples and the second
channels. If the sample index goes past the bounds of the array, it should be
transformed to an index within the range of that array. Note that such
padding functions only work on signals that are also AbstractArray objects.
You can always generate an array from a given signal by first passing it
through `sink` or `sink!`.

## See also

[`cycle`](@ref)
[`mirror`](@ref)
[`lastsample`](@ref)
[`valuefunction`](@ref)
"""
pad(p) = x -> pad(x,p)
function pad(x,p)
    x = signal(x)
    isinf(nsamples(x)) ? x : PaddedSignal(x,p)
end

"""
    lastsample

When passed as an argument to `pad`, allows padding using the last sample of a
signal. You cannot use this function in other contexts, and it will normally
throw an error. See [`pad`](@ref).
"""
lastsample(x) = error("Must be passed as argument to `pad`.")

"""
    SignalOperators.valuefunction(fn)

Returns true if `fn` should be treated as a value function. See
[`pad`](@ref). If you wish your own function to be a value function, you can
do this as follows.

    SignalOperators.valuefunction(::typeof(myfun)) = true

"""
valuefunction(x) = false
valuefunction(::typeof(lastsample)) = true

"""
    cycle(x,i,j)

An indexing function which wraps index i using mod, thus
repeating the signal when i > size(x,1). It can be passed as the second
argument to [`pad`](@ref).
"""
@Base.propagate_inbounds cycle(x,i,j) = x[(i-1)%end+1,j]

"""
    mirror(x,i,j)

An indexing function which mirrors the indices when i > size(x,1). This means
that past the end of the signal x, the signal first repeats with samples in
reverse order, then repeats in the original order, so on and so forth. It
can be passed as the second argument to  [`pad`](@ref).
"""
@Base.propagate_inbounds function mirror(x,i,j)
    function helper(i,N)
       count,remainder = divrem(i-1,N)
       iseven(count) ? remainder+1 : N-remainder
    end
    x[helper(i,end),j]
end

usepad(x::PaddedSignal,check) = usepad(x,SignalTrait(x),check)
usepad(x::PaddedSignal,s::IsSignal,check) = usepad(x,s,x.pad,check)
usepad(x::PaddedSignal,s::IsSignal{T},p::Number,check) where T =
    Fill(convert(T,p),nchannels(x.signal))
function usepad(x::PaddedSignal,s::IsSignal{T},
    p::Union{Array,Tuple},check) where T

    map(x -> convert(T,x),p)
end
usepad(x::PaddedSignal,s::IsSignal,::typeof(lastsample),check) =
    sampleat!(one_sample,x,1,nsamples(x.signal),check)
function usepad(x::PaddedSignal,s::IsSignal{T},fn::Function,check) where T
    nargs = map(x -> x.nargs - 1, methods(fn).ms)
    if 3 ∈ nargs
        if indexable(x.signal)
            fn
        else
            io = IOBuffer()
            show(io,MIME("text/plain"),x)
            sig_string = String(take!(io))
            error("Attemped to specify an indexing pad function for the ",
                  "following signal, which is not known to support ",
                  "`getindex`.\n",sig_string)
        end
    elseif 1 ∈ nargs
        if valuefunction(fn)
            fn(x.signal)
        else
            Fill(fn(T),nchannels(x.signal))
        end
    else
        error("Pad function ($fn) must take 1 or 3 arguments. ",
              "Refering `pad` help.")
    end
end

child(x::PaddedSignal) = x.signal

struct UsePad
end
const use_pad = UsePad()

struct PadCheckpoint{S,P,C} <: AbstractCheckpoint{S}
    pad::P
    child_or_index::C
end
child(x::PadCheckpoint{<:Any,Nothing}) = x.child_or_index
child(x::PadCheckpoint) = nothing
checkindex(c::PadCheckpoint{<:Any,Nothing}) = checkindex(c.child_or_index)
checkindex(c::PadCheckpoint) = c.child_or_index

atcheckpoint(x::PaddedSignal,offset::Number,stopat) =
    pad_atcheckpoint(x,offset,stopat)
atcheckpoint(x::S,offset::AbstractCheckpoint{S},stopat) where
    S <: PaddedSignal = pad_atcheckpoint(x,offset,stopat)
function pad_atcheckpoint(x::PaddedSignal,check,stopat)
    childcheck = isnothing(child(check)) ? nothing :
        atcheckpoint(child(x),child(check),min(stopat,nsamples(child(x))))
    if !isnothing(childcheck) && checkindex(childcheck) < nsamples(child(x))
        S,C = typeof(x), typeof(childcheck)
        PadCheckpoint{S,Nothing,C}(nothing,childcheck)
    else
        p = usepad(x,check)
        index = if !isnothing(childcheck)
            checkindex(childcheck)
        else
            check isa Number ? check+1 : stopat+1
        end
        S,P,C = typeof(x), typeof(p), typeof(index)
        PadCheckpoint{S,P,C}(p,index)
    end
end

@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::PadCheckpoint{S,<:Nothing}) where S <: PaddedSignal

    sampleat!(result,x.signal,i,j,child(check))
end

@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::PadCheckpoint{S,<:Function}) where S <: PaddedSignal

    writesink!(result,i,check.pad(x.signal,j,:))
end

@Base.propagate_inbounds function sampleat!(result,x::S,
    i,j,check::PadCheckpoint{S}) where S <: PaddedSignal

    writesink!(result,i,check.pad)
end

Base.show(io::IO,::MIME"text/plain",x::PaddedSignal) = pprint(io,x)
function PrettyPrinting.tile(x::PaddedSignal)
    child = signaltile(x.signal)
    operate = literal(string("pad(",x.pad,")"))
    tilepipe(child,operate)
end
signaltile(x::PaddedSignal) = PrettyPrinting.tile(x)
