using Unitful
export OperateOn, Operate, Mix, Amplify, AddChannel, SelectChannel,
    operate, mix, amplify, addchannel, selectchannel, Extend

################################################################################
# binary operators

struct MapSignal{Fn,N,C,T,Fs,El,Si,Pd,PSi} <: AbstractSignal{T}
    fn::Fn
    val::El
    signals::Si
    framerate::Fs
    padding::Pd
    padded_signals::PSi
    blocksize::Int
    bychannel::Bool
end

function MapSignal(fn::Fn,val::El,signals::Si,
    framerate::Fs,padding::Pd,blocksize::Int,bychannel::Bool) where
        {Fn,El,L,Si,Fs,Pd}

    T = El == NoValues ? Nothing : ntuple_T(El)
    N = El == NoValues ? 0 : length(signals)
    C = El == NoValues ? 1 : nchannels(signals[1])
    padded_signals = Extend.(signals,Ref(padding))
    PSi = typeof(padded_signals)
    MapSignal{Fn,N,C,T,Fs,El,Si,Pd,PSi}(fn,val,signals,framerate,padding,
        padded_signals,blocksize,bychannel)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::Type{<:MapSignal{<:Any,<:Any,<:Any,T,Fs,L}}) where {Fs,T,L} =
    IsSignal{T,Fs,L}()
nchannels(x::MapSignal) = length(x.val)
framerate(x::MapSignal) = x.framerate

function duration(x::MapSignal)
    durs = duration.(x.padded_signals)
    Ns = nframes_helper.(x.padded_signals)
    durlen = ifelse.(isknowninf.(durs),Ns ./ framerate(x),durs)
    reduce(maxlen,durlen)
end
function ToFramerate(x::MapSignal,s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,fs;blocksize)

    if inHz(fs) < x.framerate
        # reframe input if we are downsampling
        OperateOn(cleanfn(x.fn),ToFramerate.(x.signals,fs,blocksize=blocksize)...,
            padding=x.padding,bychannel=x.bychannel,
            blocksize=x.blocksize)
    else
        # reframe output if we are upsampling
        ToFramerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

root(x::MapSignal) = reduce(mergeroot,root.(x.signals))

ToFramerate(x::MapSignal,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    OperateOn(cleanfn(x.fn),ToFramerate.(x.signals,fs,blocksize=blocksize)...,
        padding=x.padding,bychannel=x.bychannel,blocksize=x.blocksize)

"""

    OperateOn(fn,arguments...;padding=default_pad(fn),bychannel=false)

Apply `fn` across the samples of the passed signals. The output length is the
maximum length of the arguments. Shorter signals are extended using
`Extend(x,padding)`.

!!! note

    There is no piped version of `OperateOn`, use [`Operate`](@ref) to pipe.
    The shorter name is used to pipe because it is expected to be the more
    common use case.

## Channel-by-channel functions (default)

When `bychannel == false` the function `fn` should treat each of its
arguments as a single number and return a single number. This operation is
broadcast across all channels of the input. It is expected to be a type
stable function.

The signals are first promoted to have the same sample rate and the same
number of channels using [`Uniform`](@ref).

## Cross-channel functions

When `bychannel=false`, rather than being applied to each channel seperately
the function `fn` is applied to each frame, containing all channels. For
example, for a two channel signal, the following would swap these two
channels.

```julia
x = rand(10,2)
swapped = OperateOn(x,bychannel=false) do val
    val[2],val[1]
end
```

The signals are first promoted to have the same sample rate, but the number of
channels of each input signal remains unchanged.

## Padding

Padding determines how frames past the end of shorter signals are reported.
If you wish to change the padding for all signals you can set the value of
the keyword argument `padding`. If you wish to specify distinct padding
values for some of the inputs, you can first call [`Extend`](@ref) on those
arguments.

The default value for `padding` is determined by the `fn` passed. A fallback
implementation of `default_pad` returns `zero`. The default value for the
four basic arithmetic operators is their identity (`one` for `*` and `zero`
for `+`).

To define a new default for a specific function, just create a new method of
`default_pad(fn)`

```julia
myfun(x,y) = x + 2y
SignalOperators.default_pad(::typeof(myfun)) = one

sink(OperateOn(myfun,Until(5,2frames),Until(2,4frames))) == [9,9,5,5]
```

"""
function OperateOn(fn,xs...;
    padding = default_pad(fn),
    bychannel = true,
    blocksize = default_blocksize)

    xs = Uniform(xs,channels=bychannel)
    fs = framerate(xs[1])

    vals = testvalue.(xs)
    MapSignal(fn,astuple(fn(vals...)),xs,fs,padding,blocksize,
        bychannel)
end

tolen(x::Extended) = x.len
tolen(x::Number) = x
tolen(x::NumberExtended) = 0
tolen(x::InfiniteLength) = inflen
tolen(x::Missing) = missing
maxlen(x,y) = max(tolen(x),tolen(y))
maxlen(x::NumberExtended,y::NumberExtended) = x
nframes_helper(x::MapSignal) = reduce(maxlen,nframes_helper.(x.signals))

"""
    Operate(fn,rest...;padding,bychannel)

Equivalent to

```julia
(x) -> OperateOn(fn,x,rest...;padding=padding,bychannel=bychannel)
````

## See also

[`OperateOn`](@ref)
"""
Operate(fn,xs...;kwds...) = x -> OperateOn(fn,x,xs...;kwds...)

"""
    operate(fn,args...;padding,bychannel)

Equivalent to `sink(OperateOn(fn,args...;padding,bychannel))`

## See also

[`OperateOn`](@ref)

"""
operate(fn,args...;kwds...) = sink(OperateOn(fn,args...;kwds...))

testvalue(x) = Tuple(zero(sampletype(x)) for _ in 1:nchannels(x))

struct EmptyChildState
end
const emptychild = EmptyChildState()
iterateblock(x,N,::EmptyChildState) = iterateblock(x,N)

struct MapSignalState{C,O}
    len::Int
    offset::Int
    children::C
    offsets::O
end
nframes(x::MapSignalState) = x.len
initstate(x::MapSignal{<:Any,N}) where N =
    MapSignalState(0,0,
        [(channeltype(x)[],emptychild) for _ in 1:N],
        Tuple(zeros(N)))

function iterateblock(x::MapSignal, N, state=initstate(x))
    maxlen = min(N,nframes(x) - (state.offset + state.len))
    (maxlen == 0) && return nothing

    offsets = map(state.offsets, state.children) do offset, (childdata, childstate)
        offset += state.len
        offset == block_nframes(childstate) ? 0 : offset
    end

    children = map(x.padded_signals,state.children,offsets) do sig, (childdata, childstate), offset
        if offset == 0
            iterateblock(x, maxlen, childstate)
        else
            (childdata, childstate)
        end
    end

    # find the smallest child state length, and use that as the length for the
    # parent state length
    len = min(maxlen,minimum(zip(children,offsets)) do (child,offset)
        if isnothing(child)
            0
        else
            childdata, childstate = child
            block_nframes(childdata) - offset
        end
    end)
    Ch, C, O = typeof(state.channels), typeof(children), typeof(offsets)
    newstate = MapSignalState{Ch,C,O}(len,state.offset + state.len,state.channels,children,
        offsets)

    if x.bychannel
        BroadcastArray(x.fn, childview.(x,state.children,state.offsets,len)...)
    else
        LazyMapLastDim(x.fn, childview.(x,state.children,state.offsets,len)...)
    end
end

function childview(parent,child,offset,len)
    if !isnothing(child)
        data, state = child
        timeslice(data,(1:len) .+ offset)
    else
        sampletype(parent)[]
    end
end

# TODO:!!
struct LazyMapLastDim{Fn,N,T}
    fn::Fn
    args::NTuple{M,<:Array{T}}
    LazyMapLastDim(fn,args...) = new(fn,args)
end


default_pad(x) = zero
default_pad(::typeof(*)) = one
default_pad(::typeof(/)) = one

Base.show(io::IO,::MIME"text/plain",x::MapSignal) = pprint(io,x)
function PrettyPrinting.tile(x::MapSignal)
    if length(x.signals) == 1
        tilepipe(signaltile(x.signals[1]),literal(string(mapstring(x.fn),")")))
    elseif length(x.signals) == 2
        operate =
            literal(mapstring(x.fn)) * signaltile(x.signals[2]) * literal(")") |
            literal(mapstring(x.fn)) / indent(4) * signaltile(x.signals[2]) /
                literal(")")
        tilepipe(signaltile(x.signals[1]),operate)
    else
        list_layout(signaltile.(collect(x.signals)),par=(mapstring(x.fn),")"))
    end
    # TODO: report the padding and bychannel values if a they are non-default
    # values
end
signaltile(x::MapSignal) = PrettyPrinting.tile(x)
mapstring(fn) = string("Operate(",fn,",")

"""

    Mix(xs...)

Sum all signals together, using [`OperateOn`](@ref). Unlike `OperateOn`,
`Mix` includes a piped version.


"""
Mix(y) = x -> Mix(x,y)
Mix(xs...) = OperateOn(+,xs...)
mapstring(::typeof(+)) = "Mix("

"""
    mix(xs...)

Equivalent to `sink(Mix(xs...))`

## See also

[`Mix`](@ref)

"""
mix(xs...) = sink(Mix(xs...))

"""

    Amplify(xs...)

Find the product, on a per-frame basis, for all signals `xs` using
[`OperateOn`](@ref). Unlike `OperateOn`, `Amplify` includes a piped
version.

"""
Amplify(y) = x -> Amplify(x,y)
Amplify(xs...) = OperateOn(*,xs...)
mapstring(::typeof(*)) = "Amplify("

"""
    amplify(xs...)

Equivalent to `sink(Amplify(xs...))`

## See also

[`Amplify`](@ref)

"""
amplify(xs...) = sink(Amplify(xs...))

"""

    AddChannel(xs...)

Concatenate the channels of all signals into one signal, using
[`OperateOn`](@ref). This will result in a signal with `sum(nchannels,xs)`
channels. Unlike `OperateOn`, `AddChannels` includes a piped
version.


"""
AddChannel(y) = x -> AddChannel(x,y)
AddChannel(xs...) = OperateOn(tuplecat,xs...;bychannel=false)
tuplecat(a,b) = (a...,b...)
tuplecat(a,b,c,rest...) = reduce(tuplecat,(a,b,c,rest...))
mapstring(::typeof(tuplecat)) = "AddChannel("

"""
    addchannel(xs...)

Equivalent to `sink(AddChannel(xs...))`.

## See also

[`AddChannel`](@ref)

"""
addchannel(xs...) = sink(AddChannel(xs...))


"""

    SelectChannel(x,n)

Select channel `n` of signal `x`, as a single-channel signal, using
[`OperateOn`](@ref). Unlike `OperateOn`, `SelectChannel` includes a piped
version.


"""
SelectChannel(n) = x -> SelectChannel(x,n)
SelectChannel(x,n) = OperateOn(GetChanFn(n),x,bychannel=false)
struct GetChanFn; n::Int; end
(fn::GetChanFn)(x) = x[fn.n]
mapstring(fn::GetChanFn) = string("SelectChannel(",fn.n)

"""
    selectchannel(xs...)

Equivalent to `sink(SelectChannel(xs...))`

## See also

[`SelectChannel`](@ref)

"""
selectchannel(xs...) = sink(SelectChannel(xs...))
