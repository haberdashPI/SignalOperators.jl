
function dictgroup(by,col)
    x = by(first(col))
    dict = Dict{typeof(x),Vector}()
    for c in col
        k = by(c)
        dict[k] = push!(get(dict,k,[]),c)
    end
    dict
end

struct ResamplerFn{T,Fs}
    ratio::T
    fs::Fs
end

SignalBase.inframes(::InfiniteLength,fs=missing) = inflen
SignalBase.inframes(::Type{T}, ::InfiniteLength,fs=missing) where T = inflen

SignalBase.inseconds(::InfiniteLength,r=missing) = inflen
SignalBase.inseconds(::Type{T},::InfiniteLength,r=missing) where T = inflen

maybeseconds(x::Number) = x*s
maybeseconds(x::Quantity) = x