using Unitful
export OperateOn, Operate, Mix, Amplify, AddChannel, SelectChannel,
    operate, mix, amplify, addchannel, selectchannel, Extend

################################################################################
# binary operators

# TODO: reduce all the type params, and set up for
# fn applying element by element or across an entire block (not just
# an entire set of channels)

struct MapSignal{El,T} <: AbstractSignal{T}
    fn
    first_value::El
    signals
    framerate
end
isblockfn(x::MapSignal{<:Number}) = false
isblockfn(x::MapSignal{<:AbstractArray}) = true

function MapSignal(fn, signals, framerate, blockfn::Bool)
    z = zero.(sampletype.(signals))
    val = blockfn ? fn(Fill.(z,Tuple.(nchannels.(signals),1))...) : fn(z...)
    El = typeof(val)
    T = blockfn ? eltype(typeof(val)) : typeof(val)
    MapSignal{El,T}(fn,val,signals,framerate)
end

struct NoValues
end
novalues = NoValues()
SignalTrait(x::MapSignal) = IsSignal()
nchannels(x::MapSignal{<:Number}) = maximum(nchannels(s) for s in x.signals)
nchannels(x::MapSignal{<:AbstractArray}) = nchannels(x.first_value)
framerate(x::MapSignal) = x.framerate

function duration(x::MapSignal)
    durs = duration.(x.signals)
    Ns = nframes_helper.(x.signals)
    durlen = ifelse.(isknowninf.(durs),Ns ./ framerate(x),durs)
    reduce(maxlen,durlen)
end
function ToFramerate(x::MapSignal,s::IsSignal{<:Any,<:Number},
    c::ComputedSignal,fs;blocksize)

    if inHz(fs) < x.framerate
        # resample input if we are downsampling
        MapSignal(x.fn,ToFramerate.(x.signals,fs,blocksize=blocksize), fs, isblockfn(x))
    else
        # resample output if we are upsampling
        ToFramerate(x,s,DataSignal(),fs,blocksize=blocksize)
    end
end

root(x::MapSignal) = reduce(mergeroot,root.(x.signals))

ToFramerate(x::MapSignal,::IsSignal{<:Any,Missing},__ignore__,fs;blocksize) =
    MapSignals(fn, ToFramerate.(x.signals,fs,blocksize=blocksize),
        fs, !(x.first_value isa Number))

"""

    OperateOn(fn,arguments...;padding=default_pad(fn),blockfn=false)

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

## Block-wise functions

When `blockfn=true`, the function is passed block of data (a read-only array)
for each input, which is some time-slice of each signal. The function
should return a an array with the same number of time samples (last array dimension)
but can change the number of channels.

For example the following command would swap the given signal's two channels.

```julia
x = rand(2,10)
swapped = OperateOn(x,blockfn=false) do block
    reverse(block,dims=size(block)[1:end-1])
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
    blockfn = true)

    xs = Uniform(xs,channels=!blockfn)
    fs = framerate(xs[1])

    MapSignal(fn,Extend.(xs,padding),fs,blockfn)
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

    children = map(x.signals,state.children,offsets) do sig, (childdata, childstate), offset
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

    if !isblockfn(x)
        BroadcastArray(x.fn, childview.(state.children,state.offsets,len)...)
    else
        x.fn(childview.(state.children,state.offsets,len)...)
    end
end

function childview(parent,child,offset,len)
    data, state = child
    timeslice(data,(1:len) .+ offset)
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
AddChannel(xs...) = OperateOn(addchanfn,xs...;blockfn=true)
addchanfn(args...) = ApplyArray(vcat, args...)
mapstring(::typeof(addchanfn)) = "AddChannel("

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
(fn::GetChanFn)(x) = view(x,fn.n,:)
mapstring(fn::GetChanFn) = string("SelectChannel(",fn.n)

"""
    selectchannel(xs...)

Equivalent to `sink(SelectChannel(xs...))`

## See also

[`SelectChannel`](@ref)

"""
selectchannel(xs...) = sink(SelectChannel(xs...))
