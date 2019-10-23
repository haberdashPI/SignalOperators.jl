export inflen

struct InfiniteLength
end

@doc """

    inflen

Represents an infinite length. Proper overloads are defined to handle
arithmetic and ordering for the infinite value.

## Missing values

For the purposes of `SignalOperators` missing values are considered
to be unknown, but of finite length. For example: `inflen * missing == inflen`.

"""
const inflen = InfiniteLength()
Base.show(io::IO,::MIME"text/plain",::InfiniteLength) =
    write(io,"inflen")

Base.isinf(::InfiniteLength) = true
isinf(x) = Base.isinf(x)
# for our purposes, missing values always denote an unknown finite value
isinf(::Missing) = false
Base.ismissing(::InfiniteLength) = false
Base.:(+)(::InfiniteLength,::Number) = inflen
Base.:(+)(::Number,::InfiniteLength) = inflen
Base.:(-)(::InfiniteLength,::Number) = inflen
Base.:(+)(::InfiniteLength,::Missing) = inflen
Base.:(+)(::Missing,::InfiniteLength) = inflen
Base.:(-)(::InfiniteLength,::Missing) = inflen
Base.isless(::Number,::InfiniteLength) = true
Base.isless(::InfiniteLength,::Number) = false
Base.isless(::InfiniteLength,::Missing) = false
Base.isless(::Missing,::InfiniteLength) = true
Base.isless(::InfiniteLength,::InfiniteLength) = false
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
