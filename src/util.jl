
function dictgroup(by,col)
    x = by(first(col))
    dict = Dict{typeof(x),Vector}()
    for c in col
        k = by(c)
        dict[k] = push!(get(dict,k,[]),c)
    end
    dict
end