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

