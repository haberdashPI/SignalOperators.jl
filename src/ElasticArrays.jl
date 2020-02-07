using .ElasticArrays

# TODO: handle tuples
function initsink(x,::Type{<:ElasticArray})
    if ismissing(nframes(x))
        ElasticArray{sampletype(x)}(nchannels(x),0)
    else
        ElasticArray{sampletype(x)}(nchannels(x),nframes(x))
    end
end

sink(x,::Type{ElasticArray}) = transpose(sink(x,ElasticArray,CutMethod(x)))

function sink!(result::ElasticArray,x,::IsSignal,block)
    written = 0
    while !isnothing(block)
        @assert nframes(block) > 0
        resize!(result,size(result)[1:end-1]...,
            size(result)[end]+nframes(block))
        sink_helper!(result,written,x,block)
        written += nframes(block)
        block = nextblock(x,maxlen,false,block)
    end

    block
end

@Base.propagate_inbounds function writesink!(result::ElasticArray,i,v)
    for ch in 1:length(v)
        result[ch,i] = v[ch]
    end
    v
end
