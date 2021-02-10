
"""
    sink(signal,[to])

Creates a given type of object (`to`) from a signal. By default the type of
the resulting sink is determined by the type of the underlying data of the
signal: e.g. if `x` is a `SampleBuf` object then `sink(Mix(x,2))` is also a
`SampleBuf` object. If there is no underlying data (`Signal(sin) |> sink`)
then a Tuple of an array and the framerate is returned.

!!! warning

    Though `sink` often makes a copy of an input array, it is not guaranteed
    to do so. For instance `sink(Until(rand(10),5frames))` will simply take a view
    of the first 5 frames of the input.

# Values for `to`

## Type

If `to` is an array type (e.g. `Array`, `DimensionalArray`) the signal is
written to a value of that type.

If `to` is a `Tuple` the result is an `Array` of samples and a number
indicating the sample rate in Hertz.

"""
sink(x) = SignalTrait(x) isa Nothing ? sig -> sink(sig, x) : sink(x, typeof(x))
sink(x, to) = sink(x, to, SignalTrait(x))
function sink(x, to, ::Nothing)
    x = Signal(x)
    sink(x, to, SignalTrait(x))
end
sink(x::T, to::Type{S}, ::IsSignal) where {T <: S, S} = x

"""
    sink!(array,x)

Write `size(array,1)` frames of signal `x` to `array`.
"""
function sink!
end

"""

## Filename

If `to` is a string, it is assumed to describe the name of a file to which
the signal will be written. You will need to call `import` or `using` on an
appropriate backend for writing to the given file type.

Available backends include the following pacakges
- [WAV](https://codecov.io/gh/haberdashPI/SignalOperators.jl/src/master/src/WAV.jl)
- [LibSndFile](https://github.com/JuliaAudio/LibSndFile.jl)

"""
sink(to::String) = x -> sink(x,to)
function sink(x,to::String)
    save_signal(filetype(to),to,x)
end
function save_signal(::Val{T},filename,x) where T
    error("No backend loaded for file of type $T. Refer to the documentation ",
          "of `Signal` to find a list of available backends.")
end

