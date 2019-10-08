using Unitful

# having these in a submodule allows the user to decide if
# they want to import the shorthand unit names (or just use e.g. u"ms")
module Units
    using Unitful
    using Unitful: Hz, s, kHz, ms, °, rad, dB

    @dimension 𝐒 "𝐒" Sample
    @refunit samples "samples" Samples 𝐒 true
    const SampDim = Unitful.Dimensions{(Unitful.Dimension{:Sample}(1//1),)}
    const SampleQuant{N} = Quantity{N,𝐒}

    const localunits = Unitful.basefactors
    const localpromotion = Unitful.promotion
    function __init__()
        merge!(Unitful.basefactors,localunits)
        merge!(Unitful.promotion, localpromotion)
    end

    export ksamples, samples, Hz, s, kHz, ms, dB, °, rad
end
using .Units
using .Units: SampleQuant

"""
    inradians([Type],x)

Given an angle value, convert to a value of Type (defaults to Float64) in
radians. Unitless numbers are assumed to be in radians and are silently
passed through.

## Examples
julia> inradians(180°) 
3.141592653589793

julia> inradians(2π)
6.283185307179586

julia> inradians(0.5π*rad)
1.5707963267948966

"""
inradians(x::Number, rate=missing) = x
inradians(x::Quantity,rate=missing) = ustrip(uconvert(rad, x))
inradians(x::Unitful.Time, rate=missing) =
    ustrip(uconvert(Unitful.NoUnits, x * inHz(rate)*Hz))*2π * rad
inradians(::Type{T},x::Number, rate=missing) where T <: Integer =
    trunc(T,inradians(x,rate))
inradians(::Type{T},x::Number, rate=missing) where T =
    convert(T,inradians(x,rate))

"""
    insamples([Type,]quantity[, rate])

Translate the given quantity to a (unitless) number of time samples,
given a particular samplerate. Note that this isn't quantized to integer numbers
of samples. If given a `Type`, the result will first be coerced to the given type.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in samples.

# Example

julia> insamples(0.5s, 44100Hz)
22050.0

"""
insamples(frame::SampleQuant, rate=missing) = ustrip(uconvert(samples, frame))
insamples(time::Unitful.Time, rate=missing) = inseconds(time)*inHz(rate)
insamples(frame::Number, rate=missing) = frame

function insamples(::Type{T}, frame::Number, rate=missing) where T
    n = insamples(frame,rate)
    ismissing(n) && return missing
    T <: Integer ? trunc(T,n) : convert(T,n)
end
insamples(::Missing,fs=missing) = missing
insamples(::Type,::Missing,fs=missing) = missing
insamples(::InfiniteLength,fs=missing) = inflen
insamples(::Type, ::InfiniteLength,fs=missing) = inflen

"""
    inHz(quantity)

Translate a particular quantity (usually a frequency) to a (unitless) value in
Hz.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in Hz.

## Examples

julia> inHz(1.0kHz)
1000.0

"""
inHz(x::Quantity) = ustrip(uconvert(Hz, x))
inHz(x::Number) = x
inHz(::Missing) = missing
inHz(::Type{T},x) where T <: Integer = trunc(T,inHz(x))
inHz(::Type{T},x) where T = convert(T,inHz(x))
inHz(::Type,x::Missing) = missing

"""
   inseconds(quantity[, rate])

Translate a particular quantity (usually a time) to a (unitless) value in
seconds.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in seconds.

For some units (e.g. samples) you will need to specify a sample rate:

## Examples
julia> inseconds(50.0ms)
0.05

julia> inseconds(441samples, 44100Hz)
0.01

"""
inseconds(x::Unitful.Time, rate=missing) = ustrip(uconvert(s,x))
inseconds(x::SampleQuant, rate=missing) = insamples(x,rate) / inHz(rate)
function inseconds(x::Quantity, rate=missing)
    error("Don't know how to convert $x to seconds.")
end
inseconds(x::Number, rate=missing) = x
function inseconds(::Type{T},x::Number,rate=missing) where T
    n = inseconds(x,rate)
    ismissing(n) && return missing
    T <: Integer ? trunc(T,n) : convert(T,n)
    convert(T,inseconds(x,rate))
end
inseconds(::Missing,r=missing) = missing
inseconds(::Type,::Missing,r=missing) = missing
inseconds(::InfiniteLength,r=missing) = inflen
inseconds(::Type,::InfiniteLength,r=missing) = inflen

maybeseconds(n::Number) = n*s
maybeseconds(n::Quantity) = n