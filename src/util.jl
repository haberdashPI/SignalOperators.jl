
function dictgroup(by,col)
    x = by(first(col))
    dict = Dict{typeof(x),Vector{typeof(first(col))}}()
    for c in col
        k = by(c)
        dict[k] = push!(get(dict,k,typeof(c)[]),c)
    end
    dict
end

function mergechecks(body,children,offset,len)
    checks = mapreduce(@λ(checkpoints(_,offset,len)),vcat,children)
    map(dictgroup(checkindex,checks)) do (i,c)
        body(i,Tuple(c))
    end
end
