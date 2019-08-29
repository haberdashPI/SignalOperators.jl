using AxisArrays

# signals can be an AxisArray
function SignalTrait(x::AxisArray)
    times = axisvalues(x,Axis{:time})
    IsSignal(1/step(times))
end

function samples(x::AxisArray,::IsSignal) 
    if 1 ≤ ndims(x) ≤ 2
        error("Expected AxisArray to have one or two dimensions")
    end

    if axisdim(x,Axis{:time}) == 1
        TimeSlices{size(x,1)}(x,samplerate(x))
    else
        TimeSlices{size(x,1),2}(x,samplerate(x))
    end
end

function sink(x::AxisArray)
    if axisdim(x,Axis{:time}) == 1
        x
    else
        permutedims(x,[2,1])
    end
end

function AxisArray(x::AbstractSignal)
    times = Axis{:time}(range(0s,length=nsamples(x),step=s/samplerate(x)))
    channels = Axis{:channel}(1:nchannels(x))
    AxisArray(sink(x),times,channels)
end