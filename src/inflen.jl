export inflen

abstract type Infinite
end
struct InfiniteLength <: Infinite
end

@doc """

    inflen

Represents an infinite length. Proper overloads are defined to handle
arithmetic and ordering for the infinite value.

"""
const inflen = InfiniteLength()
Base.show(io::IO,::MIME"text/plain",::InfiniteLength) =
    write(io,"inflen")

Base.isinf(::Infinite) = true
isknowninf(x) = isinf(x)
isknowninf(::Missing) = false

Base.ismissing(::Infinite) = false
Base.:(+)(x::Infinite,::Number) = x
Base.:(+)(::Number,x::Infinite) = x
Base.:(-)(x::Infinite,::Number) = x
Base.:(+)(x::Infinite,::Missing) = x
Base.:(+)(::Missing,x::Infinite) = x
Base.:(-)(x::Infinite,::Missing) = x
Base.isless(::Number,::Infinite) = true
Base.isless(::Infinite,::Number) = false
Base.isless(::Infinite,::Missing) = false
Base.isless(::Missing,::Infinite) = true
Base.isless(::Infinite,::Infinite) = false
Base.:(*)(x::Infinite,::Number) = x
Base.:(*)(::Number,x::Infinite) = x
Base.:(*)(x::Infinite,::Missing) = x
Base.:(*)(::Missing,x::Infinite) = x
Base.:(*)(x::Infinite,::Unitful.FreeUnits) = x
Base.:(/)(x::Infinite,::Number) = x
Base.:(/)(x::Infinite,::Missing) = x
Base.:(/)(::Number,::Infinite) = 0
Base.:(/)(::Missing,::Infinite) = 0
Base.ceil(::T,x::Infinite) where T = x
Base.ceil(x::Infinite) = x
Base.floor(::T,x::Infinite) where T = x
Base.floor(x::Infinite) = x
Base.clamp(x::Infinite,min,max) = max
Base.clamp(x::Number,min,max::Infinite) = max(x,min)

Base.length(::Infinite) = 1
Base.iterate(x::Infinite) = x, nothing
Base.iterate(::Infinite,::Nothing) = nothing