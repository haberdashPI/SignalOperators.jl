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
Base.:(+)(::InfiniteLength,::Number) = inflen
Base.:(+)(::Number,::InfiniteLength) = inflen
Base.:(-)(::InfiniteLength,::Number) = inflen
Base.:(+)(::InfiniteLength,::Missing) = inflen
Base.:(+)(::Missing,::InfiniteLength) = inflen
Base.:(-)(::InfiniteLength,::Missing) = inflen
Base.isless(::Number,::Infinite) = true
Base.isless(::Infinite,::Number) = false
Base.isless(::Infinite,::Missing) = false
Base.isless(::Missing,::Infinite) = true
Base.isless(::Infinite,::Infinite) = false
Base.:(*)(::InfiniteLength,::Number) = inflen
Base.:(*)(::Number,::InfiniteLength) = inflen
Base.:(*)(::InfiniteLength,::Missing) = inflen
Base.:(*)(::Missing,::InfiniteLength) = inflen
Base.:(*)(::InfiniteLength,::Unitful.FreeUnits) = inflen
Base.:(/)(::InfiniteLength,::Number) = inflen
Base.:(/)(::InfiniteLength,::Missing) = inflen
Base.:(/)(::Number,::InfiniteLength) = 0
Base.:(/)(::Missing,::InfiniteLength) = 0
Base.ceil(::T,::InfiniteLength) where T = inflen
Base.ceil(::InfiniteLength) = inflen
Base.floor(::T,::InfiniteLength) where T = inflen
Base.floor(::InfiniteLength) = inflen

Base.length(::Infinite) = 1
Base.iterate(::Infinite) = inflen, nothing
Base.iterate(::Infinite,::Nothing) = nothing

struct LowerBoundedRange{T}
    val::T
end
(::Base.Colon)(start::Number,::InfiniteLength) = LowerBoundedRange(start)
Base.Broadcast.broadcasted(::typeof(+),lower::LowerBoundedRange,x::Number) =
    LowerBoundedRange(lower.val + x)
function Base.intersect(x::UnitRange,y::LowerBoundedRange)
    if last(x) < y.val
        1:0
    elseif first(x) < y.val
        y.val:last(x)
    else
        x
    end
end
