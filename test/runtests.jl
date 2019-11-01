using SignalOperators, SignalOperators.Units
using SignalOperators: SignalTrait, IsSignal

using LambdaFn
using Test
using Statistics
using WAV
using AxisArrays
using FixedPointNumbers
using Unitful
using ProgressMeter
using BenchmarkTools
using Statistics

using DSP
dB = SignalOperators.Units.dB

test_wav = "test.wav"
example_wav = "example.wav"
examples_wav = "examples.wav"
test_files = [test_wav,example_wav,examples_wav]

const total_test_groups = 29
progress = Progress(total_test_groups,desc="Running tests...")

@testset "SignalOperators.jl" begin

    @testset "Unit Conversions" begin
        @test SignalOperators.insamples(1s,44.1kHz) == 44100
        @test SignalOperators.insamples(Int,0.5s,44.1kHz) == 22050
        @test SignalOperators.insamples(Int,5samples) == 5
        @test SignalOperators.insamples(Int,5) == 5
        @test SignalOperators.insamples(5) == 5
        @test SignalOperators.insamples(1.0s,44.1kHz) isa Float64
        @test ismissing(SignalOperators.insamples(missing))
        @test ismissing(SignalOperators.insamples(Int,missing))
        @test ismissing(SignalOperators.insamples(Int,missing,5))
        @test ismissing(SignalOperators.insamples(missing,5))
        @test ismissing(SignalOperators.insamples(10s))

        @test SignalOperators.inHz(10) === 10
        @test SignalOperators.inHz(10Hz) === 10
        @test SignalOperators.inHz(Float64,10Hz) === 10.0
        @test SignalOperators.inHz(Int,10.5Hz) === 10
        @test ismissing(SignalOperators.inHz(missing))

        @test SignalOperators.inseconds(50ms) == 1//20
        @test SignalOperators.inseconds(50ms,10Hz) == 1//20
        @test SignalOperators.inseconds(10samples,10Hz) == 1
        @test SignalOperators.inseconds(1s,44.1kHz) == 1
        @test SignalOperators.inseconds(1,44.1kHz) == 1
        @test SignalOperators.inseconds(1) == 1
        @test ismissing(SignalOperators.inseconds(missing))
        @test SignalOperators.maybeseconds(2) == 2s
        @test SignalOperators.maybeseconds(5samples) == 5samples


        @test SignalOperators.inradians(15) == 15
        @test_throws Unitful.DimensionError SignalOperators.inradians(15samples)
        @test SignalOperators.inradians(180°) ≈ π
        @test ismissing(SignalOperators.inseconds(2samples))
    end
    next!(progress)

    @testset "Function Currying" begin
        x = signal(1,10Hz)
        @test isa(mix(x),Function)
        @test isa(amplify(x),Function)
        @test isa(bandpass(200Hz,400Hz),Function)
        @test isa(lowpass(200Hz),Function)
        @test isa(highpass(200Hz),Function)
        @test isa(ramp(10ms),Function)
        @test isa(rampon(10ms),Function)
        @test isa(rampoff(10ms),Function)
        @test isa(fadeto(x),Function)
        @test isa(amplify(20dB),Function)
        @test isa(addchannel(x),Function)
        @test isa(channel(1),Function)
        @test isa(filtersignal(x -> x),Function)
    end
    next!(progress)

    @testset "Basic signals" begin
        @test SignalTrait(signal([1,2,3,4],10Hz)) isa IsSignal
        @test SignalTrait(signal(1:100,10Hz)) isa IsSignal
        @test SignalTrait(signal(1,10Hz)) isa IsSignal
        @test SignalTrait(signal(sin,10Hz)) isa IsSignal
        @test SignalTrait(signal(randn,10Hz)) isa IsSignal
        @test_throws ErrorException signal(x -> [1,2],5Hz)
        noise = signal(randn,50Hz) |> until(5s)
        @test isapprox(noise |> sink |> mean,0,atol=0.3)
        z = signal(0,10Hz) |> until(5s)
        @test all(z |> sink .== 0)
        o = signal(1,10Hz) |> until(5s)
        @test all(o |> sink .== 1)
        @test_throws ErrorException signal(rand(5),10Hz) |> signal(5Hz)
        @test_throws ErrorException signal(randn,10Hz) |> signal(5Hz)
        @test_throws ErrorException signal(rand(5),10Hz) |> sink(duration=10samples)
    end
    next!(progress)

    @testset "Function signals" begin
        @test sink(signal(sin,ω=5Hz,ϕ=π),duration=1s,samplerate=20Hz) ==
            sink(signal(sin,ω=5Hz,ϕ=π*rad),duration=1s,samplerate=20Hz)
        @test sink(signal(sin,ω=5Hz,ϕ=π),duration=1s,samplerate=20Hz) ==
            sink(signal(sin,ω=5Hz,ϕ=100ms),duration=1s,samplerate=20Hz)
        @test sink(signal(sin,ω=5Hz,ϕ=π),duration=1s,samplerate=20Hz) ==
            sink(signal(sin,ω=5Hz,ϕ=180°),duration=1s,samplerate=20Hz)
        @test sink(signal(sin,ϕ=1s),duration=1s,samplerate=20Hz) ≈
            sink(signal(sin,ω=1Hz,ϕ=0),duration=1s,samplerate=20Hz)
        @test_throws ErrorException sink(signal(sin,ϕ=2π*rad),duration=1s,
            samplerate=20Hz)

        @test signal(identity,ω=2Hz,10Hz) |> sink(duration=10samples) |>
            duration == 1.0
    end
    next!(progress)

    @testset "Sink to arrays" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s) |> sink
        @test tone[1] .< tone[110] # verify bump of sine wave
    end
    next!(progress)

    @testset "Files as signals" begin
        tone = signal(range(0,1,length=4),10Hz) |> sink(test_wav)
        @test SignalTrait(signal(test_wav)) isa IsSignal
        @test isapprox(signal(test_wav), range(0,1,length=4),rtol=1e-6)
    end
    next!(progress)

    @testset "Change channel Count" begin
        tone = signal(sin,22Hz,ω=10Hz) |> until(5s)
        @test (tone |> tochannels(2) |> nchannels) == 2
        @test (tone |> tochannels(1) |> nchannels) == 1
        data = tone |> tochannels(2) |> sink
        @test size(data,2) == 2
        data2 = signal(data,22Hz) |> tochannels(1) |> sink
        @test size(data2,2) == 1

        @test_throws ErrorException tone |> tochannels(2) |> tochannels(3)
    end
    next!(progress)

    @testset "Cutting Operators" begin
        for nch in 1:2
            tone = signal(sin,44.1kHz,ω=100Hz) |> tochannels(nch) |> until(5s)
            @test !isinf(nsamples(tone))
            @test nsamples(tone) == 44100*5

            x = rand(12,nch)
            cutarray = signal(x,6Hz) |> after(0.5s) |> until(1s)
            @test nsamples(cutarray) == 6
            cutarray = signal(x,6Hz) |> until(1s) |> after(0.5s)
            @test nsamples(cutarray) == 3
            cutarray = signal(x,6Hz) |> until(1s) |> until(0.5s)
            cutarray2 = signal(x,6Hz) |> until(0.5s)
            @test sink(cutarray) == sink(cutarray2)

            x = rand(12,nch) |> signal(6Hz)
            @test append(until(x,1s),after(x,1s)) |> nsamples == 12

            aftered = tone |> after(2s)
            @test nsamples(aftered) == 44100*3
        end
    end
    next!(progress)

    @testset "Padding" begin
        for nch in 1:3
            tone = signal(sin,22Hz,ω=10Hz) |> tochannels(nch) |> until(5s) |>
                pad(zero) |> until(7s) |> sink
            @test mean(abs.(tone[1:22*5,:])) > 0
            @test mean(abs.(tone[22*5:22*7,:])) == 0

            tone = signal(sin,22Hz,ω=10Hz) |> until(5s) |> pad(0) |>
                until(7s) |> sink
            @test mean(abs.(tone[1:22*5,:])) > 0
            @test mean(abs.(tone[22*5:22*7,:])) == 0

            @test rand(10,nch) |> signal(10Hz) |> pad(zero) |> after(15samples) |>
                until(10samples) |> sink == zeros(10,nch)

            x = 5ones(5,nch)
            result = pad(x,zero) |> until(10samples) |> sink(samplerate=10Hz)
            all(iszero,result[6:10,:])

            x = rand(10,nch) |> signal(10Hz)
            result = pad(x,cycle) |> until(30samples) |> sink
            @test result == vcat(x,x,x)
            result = pad(x,mirror) |> until(30samples) |> sink
            @test result == vcat(x,reverse(x,dims=1),x)
            result = pad(x,lastsample) |> until(15samples) |> sink
            @test all(result[11:end,:] .== result[10:10,:])

            x = signal(sin,10Hz) |> tochannels(nch) |> until(1s)
            @test_throws ErrorException pad(x,cycle) |> sink
            @test_throws ErrorException pad(x,mirror) |> sink
            result = pad(x,lastsample) |> until(15samples) |> sink
            @test all(result[11:end,:] .== result[10:10,:])
            padv = rand(nch)
            result = pad(x,padv) |> until(15samples) |> sink
            @test all(result[11:end,:] .== padv')
        end
    end
    next!(progress)

    @testset "Appending" begin
        for nch in 1:2
            a = signal(sin,22Hz,ω=10Hz) |> tochannels(nch) |> until(5s)
            b = signal(sin,22Hz,ω=5Hz) |> tochannels(nch) |> until(5s)
            tones = a |> append(b)
            @test duration(tones) == 10
            @test nsamples(sink(tones)) == 220

            x = append(
                    rand(10,nch) |> after(0.5s),
                    signal(sin) |> tochannels(nch) |> until(0.5s)) |>
                tosamplerate(2kHz) |> sink
            @test duration(x) ≈ 0.5

            @test_throws ErrorException append(sin,1:10)
            @test SignalTrait(append(1:10,sin)) isa IsSignal
        end
    end
    next!(progress)

    @testset "Mixing" begin
        for nch in 1:2
            a = signal(sin,30Hz,ω=10Hz) |> tochannels(2) |> until(2s)
            b = signal(sin,30Hz,ω=5Hz) |> tochannels(2) |> until(2s)
            complex = mix(a,b)
            @test duration(complex) == 2
            @test nsamples(sink(complex)) == 60
        end

        x = rand(20,SignalOperators.MAX_CHANNEL_STACK+1)
        y = rand(20,SignalOperators.MAX_CHANNEL_STACK+1)
        @test (mix(x,y) |> sink(samplerate=20Hz)) == (x .+ y)

        x = rand(20,2)
        result = mapsignal(reverse,x,bychannel=false) |> sink(samplerate=20Hz)
        @test result == [x[:,2] x[:,1]]
    end
    next!(progress)

    @testset "Handling of padded mix and amplify" begin
        for nch in 1:2
            fs = 3Hz
            a = signal(2,fs) |> tochannels(nch) |> until(2s) |> append(signal(3,fs)) |> until(4s)
            b = signal(3,fs) |> tochannels(nch) |> until(3s)

            result = mix(a,b) |> sink
            for ch in 1:nch
                @test all(result[:,ch] .== [
                    fill(2,3*2) .+ fill(3,3*2);
                    fill(3,3*1) .+ fill(3,3*1);
                    fill(3,3*1)
                ])
            end

            result = amplify(a,b) |> sink
            for ch in 1:nch
                @test all(result[:,ch] .== [
                    fill(2,3*2) .* fill(3,3*2);
                    fill(3,3*1) .* fill(3,3*1);
                    fill(3,3*1)
                ])
            end
        end

        x = rand(10,2)
        y = rand(5,2)
        z = ones(10,4)
        signal(x,10Hz) |> addchannel(y) |> sink!(z)
        @test all(iszero,z[6:10,3:4])
    end
    next!(progress)

    @testset "Filtering" begin
        for nch in 1:2
            a = signal(sin,100Hz,ω=10Hz) |> tochannels(nch) |> until(5s)
            b = signal(sin,100Hz,ω=5Hz) |> tochannels(nch) |> until(5s)
            cmplx = mix(a,b)
            high = cmplx |> highpass(8Hz,method=Chebyshev1(5,1)) |> sink
            low = cmplx |> lowpass(6Hz,method=Butterworth(5)) |> sink
            highlow = low |>  highpass(8Hz,method=Chebyshev1(5,1)) |> sink
            bandp1 = cmplx |> bandpass(20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
            bandp2 = cmplx |> bandpass(2Hz,12Hz,method=Chebyshev1(5,1)) |> sink
            bands1 = cmplx |> bandstop(20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
            bands2 = cmplx |> bandstop(2Hz,12Hz,method=Chebyshev1(5,1)) |> sink

            @test_throws ErrorException highpass(a,75Hz)
            @test_throws ErrorException lowpass(a,75Hz)
            @test_throws ErrorException bandpass(a,75Hz,80Hz)
            @test_throws ErrorException bandstop(a,75Hz,80Hz)

            @test nsamples(high) == 500
            @test nsamples(low) == 500
            @test nsamples(highlow) == 500
            @test mean(high) < 0.01
            @test mean(low) < 0.02
            @test 10mean(abs,highlow) < mean(abs,low)
            @test 10mean(abs,highlow) < mean(abs,high)
            @test 10mean(abs,bandp1) < mean(abs,bandp2)
            @test 10mean(abs,bands2) < mean(abs,bands1)

            @test mean(abs,cmplx |> amplify(10) |> normpower |> sink) <
                mean(abs,cmplx |> amplify(10) |> sink)

            # proper filtering of blocks
            high2_ = cmplx |> highpass(8Hz,method=Chebyshev1(5,1),blocksize=100)
            @test high2_.blocksize == 100
            high2 = high2_ |> sink
            @test sink(high2) ≈ sink(high)

            # proper state of cut filtered signal (with blocks)
            high3 = cmplx |> highpass(8Hz,method=Chebyshev1(5,1),blocksize=64) |>
                after(1s)
            @test sink(high3) ≈ sink(high)[1s .. 5s]

            # custom filter interface
            high4 = cmplx |>
                filtersignal(digitalfilter(Highpass(8,fs=samplerate(cmplx)),
                                        Chebyshev1(5,1)))
            @test sink(high) == sink(high4)
        end
    end
    next!(progress)

    @testset "Ramps" begin
        for nch in 1:2
            tone = signal(sin,100Hz,ω=10Hz) |> tochannels(nch) |> until(5s)
            ramped = signal(sin,100Hz,ω=10Hz) |> tochannels(nch) |> until(5s) |>
                ramp(100ms) |> sink
            @test mean(abs,ramped[1:5]) < mean(abs,ramped[6:10])
            @test mean(abs,ramped) < mean(abs,sink(tone))
            @test mean(ramped) < 1e-4

            x = signal(sin,22Hz,ω=10Hz) |> tochannels(nch) |> until(2s)
            y = signal(sin,22Hz,ω=5Hz) |> tochannels(nch) |> until(2s)
            fading = fadeto(x,y,100ms)
            result = sink(fading)
            @test nsamples(fading) == ceil(Int,(2+2-0.1)*22)
            @test nsamples(result) == nsamples(fading)
            @test result[1:35,:] == sink(x)[1:35,:]
            @test result[48:end,:] == sink(y)[6:end,:]

            ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> tochannels(nch) |>
                until(100ms) |> ramp(identity) |> sink
            @test mean(abs,ramped2[1:5,:]) < mean(abs,ramped2[6:10,:])
            ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> tochannels(nch) |>
                until(100ms) |> rampon(identity) |> sink
            @test mean(abs,ramped2[1:5,:]) < mean(abs,ramped2[6:10,:])
            ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> tochannels(nch) |>
                until(100ms) |> rampoff(identity) |> sink
            @test mean(abs,ramped2[7:10,:]) < mean(abs,ramped2[1:6,:])
        end
    end
    next!(progress)

    @testset "Resampling" begin
        for nch in 1:2
            tone = signal(sin,20Hz,ω=5Hz) |> tochannels(nch) |> until(5s)
            resamp = tosamplerate(tone,40Hz)
            @test samplerate(resamp) == 40
            @test nsamples(resamp) == 2nsamples(tone)

            downsamp = tosamplerate(tone,10Hz)
            @test samplerate(downsamp) == 10
            @test nsamples(downsamp) == 0.5nsamples(tone)
            @test sink(downsamp) |> nsamples == nsamples(downsamp)


            x = rand(10,nch) |> tosamplerate(2kHz) |> sink
            @test samplerate(x) == 2000



            toned = tone |> sink
            resamp = tosamplerate(toned,40Hz)
            @test samplerate(resamp) == 40

            resampled = resamp |> sink
            @test nsamples(resampled) == 2nsamples(tone)

            # test multi-block resampling
            resamp = tosamplerate(toned,40Hz,blocksize=64)
            resampled2 = sink(resamp)
            @test nsamples(resampled) == 2nsamples(tone)
            @test resampled ≈ resampled2

            # verify that the state of the filter is proplery reset
            # (so it should produce same output a second time)
            resampled3 = resamp |> sink
            @test resampled2 ≈ resampled3

            padded = tone |> pad(one) |> until(7s)
            resamp = tosamplerate(padded,40Hz)
            @test nsamples(resamp) == 7*40
            @test resamp |> sink |> size == (7*40,nch)

            @test tosamplerate(tone,20Hz) === tone

            a = signal(sin,48Hz,ω=10Hz) |> tochannels(nch) |> until(3s)
            b = signal(sin,48Hz,ω=5Hz) |> tochannels(nch) |> until(3s)
            cmplx = mix(a,b)
            high = cmplx |> highpass(8Hz,method=Chebyshev1(5,1))
            resamp_high = tosamplerate(high,24Hz)
            @test resamp_high |> sink |> size == (72,nch)

            resamp_twice = tosamplerate(toned,15Hz) |> tosamplerate(50Hz)
            @test resamp_twice isa SignalOperators.FilteredSignal
            @test SignalOperators.child(resamp_twice) === toned
        end
    end
    next!(progress)

    @testset "Automatic reformatting" begin
        a = signal(sin,200Hz,ω=10Hz) |> tochannels(2) |> until(5s)
        b = signal(sin,100Hz,ω=5Hz) |> until(3s)
        complex = mix(a,b)
        @test nchannels(complex) == 2
        @test samplerate(complex) == 200
        @test nsamples(complex |> sink) == 1000
        more = mix(a,b,1)
        @test nsamples(more |> sink) == 1000
    end
    next!(progress)

    @testset "Axis Arrays" begin
        x = AxisArray(ones(20),Axis{:time}(range(0s,2s,length=20)))
        proc = signal(x) |> ramp |> sink
        @test size(proc,1) == size(x,1)
    end
    next!(progress)


    @testset "Operating over empty signals" begin
        for nch in 1:2
            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |>
                until(10samples) |> until(0samples)
            @test nsamples(tone) == 0
            @test mapsignal(-,tone) |> nsamples == 0
        end
    end
    next!(progress)

    @testset "normpower" begin
        for nch in 1:2
            tone = signal(sin,10Hz,ω=2Hz) |> tochannels(nch) |> until(2s) |>
                ramp |> normpower
            @test all(sqrt.(mean(sink(tone).^2,dims=1)) .≈ 1)

            resamp = tone |> tosamplerate(20Hz) |> sink
            @test all(sqrt.(mean(sink(resamp).^2,dims=1)) .≈ 1)
        end
    end
    next!(progress)

    @testset "Handling of arrays/numbers" begin
        stereo = signal([10.0.*(1:10) 5.0.*(1:10)],5Hz)
        @test stereo |> nchannels == 2
        @test stereo |> sink |> size == (10,2)
        @test stereo |> until(5samples) |> sink |> size == (5,2)
        @test stereo |> after(5samples) |> sink |> size == (5,2)

        for nch in 1:2
            # Numbers
            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |> mix(1.5) |>
                until(5s) |> sink
            @test all(tone .>= 0.5)
            x = signal(1,5Hz) |> tochannels(nch) |> until(5s) |> sink
            @test x isa AbstractArray{Int}

            @test all(10 |> tochannels(nch) |> until(1s) |>
                sink(samplerate=10Hz) .== 10)

            dc_off = signal(1,10Hz) |> tochannels(nch) |> until(1s) |>
                amplify(20dB) |> sink
            @test all(dc_off .== 10)
            dc_off = signal(1,10Hz) |> tochannels(nch) |> until(1s) |>
                amplify(40dB) |> sink
            @test all(dc_off .== 100)

            # AbstractArrays
            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |>
                mix(10.0.*(1:10)) |> sink
            @test all(tone[1:10,:] .>= 10.0*(1:10))
            x = signal(10.0.*(1:10),5Hz) |> tochannels(nch) |> until(1s) |> sink
            @test x isa AbstractArray{Float64}
            @test signal(10.0.*(1:10),5Hz) |> tochannels(nch) |>
                SignalOperators.channel_eltype == Float64
        end

        # AxisArray
        x = AxisArray(rand(2,10),Axis{:channel}(1:2),
            Axis{:time}(range(0,1,length=10)))
        @test x |> until(500ms) |> sink |> size == (4,2)

        # poorly shaped arrays
        @test_throws ErrorException signal(rand(2,2,2))
    end
    next!(progress)

    @testset "Handling of infinite signals" begin
        for nch in 1:2
            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |>
                until(10samples) |> after(5samples) |> after(2samples)
            @test nsamples(tone) == 3
            @test size(sink(tone)) == (3,nch)

            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |>
                after(5samples) |> until(5samples)
            @test nsamples(tone) == 5
            @test size(sink(tone)) == (5,nch)
            @test sink(tone)[1] > 0.9

            tone = signal(sin,200Hz,ω=10Hz) |> tochannels(nch) |>
                until(10samples) |> after(5samples)
            @test nsamples(tone) == 5
            @test size(sink(tone)) == (5,nch)
            @test sink(tone)[1] > 0.9

            @test_throws ErrorException signal(sin,200Hz) |> normpower |> sink(duration=1s)

            @test_throws ErrorException signal(sin,200Hz) |> tochannels(nch) |>
                sink
        end
    end
    next!(progress)

    @testset "Test that non-signals correctly error" begin
        x = r"nonsignal"
        @test_throws ErrorException x |> samplerate
        @test_throws ErrorException x |> sink(samplerate=10Hz)
        @test_throws ErrorException x |> duration
        @test_throws ErrorException x |> until(5s)
        @test_throws ErrorException x |> after(2s)
        @test_throws ErrorException x |> nsamples
        @test_throws ErrorException x |> nchannels
        @test_throws ErrorException x |> pad(zero)
        @test_throws ErrorException x |> lowpass(3Hz)
        @test_throws ErrorException x |> normpower
        @test_throws ErrorException x |> channel(1)
        @test_throws ErrorException x |> ramp

        x = rand(5,2)
        y = r"nonsignal"
        @test_throws ErrorException x |> append(y)
        @test_throws ErrorException x |> mix(y)
        @test_throws ErrorException x |> addchannel(y)
        @test_throws ErrorException x |> fadeto(y)
    end
    next!(progress)

    @testset "Handle of frame units" begin
        x = signal(rand(100,2),10Hz)
        y = signal(rand(50,2),10Hz)

        @test x |> until(30samples) |> sink |> nsamples == 30
        @test x |> after(30samples) |> sink |> nsamples == 70
        @test x |> append(y) |> after(20samples) |> sink |> nsamples == 130
        @test x |> append(y) |> until(130samples) |> sink |> nsamples == 130
        @test x |> pad(zero) |> until(150samples) |> sink |> nsamples == 150

        @test x |> ramp(10samples) |> sink |> nsamples == 100
        @test x |> fadeto(y,10samples) |> sink |> nsamples > 100
    end
    next!(progress)

    function showstring(x)
        io = IOBuffer()
        show(io,MIME("text/plain"),x)
        String(take!(io))
    end

    @testset "Handle printing" begin
        x = signal(rand(100,2),10Hz)
        y = signal(rand(50,2),10Hz)
        @test signal(sin,22Hz,ω=10Hz,ϕ=π/4) |> showstring ==
            "signal(sin,ω=10,ϕ=0.125π) (22.0 Hz)"
        @test signal(2dB,10Hz) |> showstring ==
            "2.0000000000000004 dB (10.0 Hz)"
        @test x |> until(5s) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> until(5 s)"
        @test x |> after(2s) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> after(2 s)"
        @test x |> append(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    append(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> pad(zero) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> pad(zero)"
        @test x |> lowpass(3Hz) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> lowpass(3 Hz)"
        @test x |> normpower |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> normpower"
        @test x |> mix(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> mix(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> amplify(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    amplify(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> addchannel(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    addchannel(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> channel(1) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> channel(1)"
        @test mapsignal(identity,x) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> mapsignal(identity,)"
        @test x |> tosamplerate(20Hz) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> tosamplerate(20 Hz)"
        @test x |> tochannels(1) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> tochannels(1)"
        @test x[:,1] |> tochannels(2) |> showstring ==
            "100-element Array{Float64,1}: … (10.0 Hz) |> tochannels(2)"
        @test startswith(rand(5,2) |> filtersignal(fs -> Highpass(10,20,fs=fs)) |> showstring,
            "5×2 Array{Float64,2}: … |> filtersignal(")

        @test x |> ramp |> showstring ==
            "rampoff_fn(0.01) (10.0 Hz) |>\n    tochannels(2) |> amplify(rampon_fn(0.01) (10.0 Hz) |> tochannels(2) |>\n                                 amplify(100×2 Array{Float64,2}: … (10.0 Hz)))"
        @test x |> ramp(identity) |> showstring ==
            "rampoff_fn(0.01,identity) (10.0 Hz) |> tochannels(2) |>\n    amplify(rampon_fn(0.01,identity) (10.0 Hz) |>\n                tochannels(2) |> amplify(100×2 Array{Float64,2}: … (10.0 Hz)))"
        @test x |> fadeto(y) |> showstring ==
            "rampoff_fn(0.01) (10.0 Hz) |>\n    tochannels(2) |> amplify(100×2 Array{Float64,2}: … (10.0 Hz)) |>\n    mix(0.0 (10.0 Hz) |> until(100 samples) |> tochannels(2) |>\n            append(rampon_fn(0.01) (10.0 Hz) |> tochannels(2) |>\n                       amplify(50×2 Array{Float64,2}: … (10.0 Hz))))"
        @test x |> fadeto(y,identity) |> showstring ==
            "rampoff_fn(0.01,identity) (10.0 Hz) |>\n    tochannels(2) |> amplify(100×2 Array{Float64,2}: … (10.0 Hz)) |>\n    mix(0.0 (10.0 Hz) |> until(100 samples) |> tochannels(2) |>\n            append(rampon_fn(0.01,identity) (10.0 Hz) |> tochannels(2) |>\n                       amplify(50×2 Array{Float64,2}: … (10.0 Hz))))"
    end
    next!(progress)

    @testset "Handle lower bitrate" begin
        x = signal(rand(Float32,100,2),10Hz)
        y = signal(rand(Float32,50,2),10Hz)
        @test x |> samplerate == 10
        @test x |> sink |> eltype == Float32
        @test x |> duration == 10
        @test x |> until(5s) |> sink |> eltype == Float32
        @test x |> after(2s) |> sink |> eltype == Float32
        @test x |> nsamples == 100
        @test x |> nchannels == 2
        @test x |> append(y) |> sink |> eltype == Float32
        @test x |> append(y) |> after(2s) |> sink |> eltype == Float32
        @test x |> append(y) |> until(13s) |> sink |> eltype == Float32
        @test x |> pad(zero) |> until(15s) |> sink |> eltype == Float32
        @test x |> lowpass(3Hz) |> sink |> eltype == Float32
        @test x |> normpower |> amplify(-10f0*dB) |> sink |> eltype == Float32
        @test x |> mix(y) |> sink(samplerate=10Hz) |> eltype == Float32
        @test x |> addchannel(y) |> sink(samplerate=10Hz) |> eltype == Float32
        @test x |> channel(1) |> sink(samplerate=10Hz) |> eltype == Float32

        @test x |> ramp |> sink |> eltype == Float32
        @test x |> fadeto(y) |> sink |> eltype == Float32
    end
    next!(progress)

    @testset "Handle fixed point numbers" begin
        x = signal(rand(Fixed{Int16,15},100,2),10Hz)
        y = signal(rand(Fixed{Int16,15},50,2),10Hz)
        @test x |> samplerate == 10
        @test x |> sink |> samplerate == 10
        @test x |> duration == 10
        @test x |> until(5s) |> duration == 5
        @test x |> after(2s) |> duration == 8
        @test x |> nsamples == 100
        @test x |> nchannels == 2
        @test x |> until(3s) |> sink |> nsamples == 30
        @test x |> after(3s) |> sink |> nsamples == 70
        @test x |> append(y) |> sink |> nsamples == 150
        @test x |> append(y) |> after(2s) |> sink |> nsamples == 130
        @test x |> append(y) |> until(13s) |> sink |> nsamples == 130
        @test x |> pad(zero) |> until(15s) |> sink |> nsamples == 150
        @test x |> lowpass(3Hz) |> sink |> nsamples == 100
        @test x |> normpower |> amplify(-10dB) |> sink |> nsamples == 100
        @test x |> mix(y) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> addchannel(y) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> channel(1) |> sink(samplerate=10Hz) |> nsamples == 100

        @test x |> ramp |> sink |> nsamples == 100
        @test x |> fadeto(y) |> sink |> nsamples == 150
    end
    next!(progress)

    @testset "Handle unknown sample rates" begin
        x = rand(100,2)
        y = rand(50,2)
        @test x |> samplerate |> ismissing
        @test x |> sink(samplerate=10Hz) |> samplerate == 10
        @test x |> tosamplerate(10Hz) |> samplerate == 10
        @test x |> duration |> ismissing
        @test x |> until(5s) |> duration |> ismissing
        @test x |> after(2s) |> duration |> ismissing
        @test x |> nsamples == 100
        @test x |> nchannels == 2
        @test x |> sink(samplerate=10Hz) |> samplerate == 10
        @test x |> until(3s) |> sink(samplerate=10Hz) |> nsamples == 30
        @test x |> after(3s) |> sink(samplerate=10Hz) |> nsamples == 70
        @test x |> append(y) |> sink(samplerate=10Hz) |> nsamples == 150
        @test x |> append(y) |> after(2s) |> sink(samplerate=10Hz) |>
            nsamples == 130
        @test x |> append(y) |> until(13s) |> sink(samplerate=10Hz) |>
            nsamples == 130
        @test x |> pad(zero) |> until(15s) |> sink(samplerate=10Hz) |>
            nsamples == 150
        @test x |> lowpass(3Hz) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> normpower |> amplify(-10dB) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> mix(y) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> addchannel(y) |> sink(samplerate=10Hz) |> nsamples == 100
        @test x |> channel(1) |> sink(samplerate=10Hz) |> nsamples == 100

        # TODO: improve implementation to remove these errors
        @test_throws ErrorException x |> ramp |> sink(samplerate=10Hz)
        @test_throws ErrorException x |> fadeto(y) |> sink(samplerate=10Hz)
    end
    next!(progress)

    # try out more complicated combinations of various features
    @testset "Stress tests" begin
        # append, dropping the first signal entirely
        a = until(sin,2s)
        b = until(cos,2s)
        x = append(a,b) |> after(3s)
        @test sink(x,samplerate=20Hz) == b |> after(1s) |> sink(samplerate=20Hz)

        noise = signal(randn,20Hz) |> until(1s) |> sink

        # filtering in combination with `after`
        x = noise |> lowpass(7Hz) |> until(4s)
        afterx = noise |> lowpass(7Hz) |> until(4s) |> after(2s)
        @test sink(x)[2s .. 4s] ≈ sink(afterx)

        # multiple sample rates
        x = signal(sin,ω=10Hz,20Hz) |> until(4s) |> sink |>
            tosamplerate(30Hz) |> lowpass(10Hz) |> fadeto(signal(sin,ω=5Hz)) |>
            tosamplerate(20Hz)
        @test samplerate(x) == 20

        x = signal(sin,ω=10Hz,20Hz) |> until(4s) |> sink |>
            tosamplerate(30Hz) |> lowpass(10Hz) |> fadeto(signal(sin,ω=5Hz)) |>
            tosamplerate(25Hz) |> sink
        @test samplerate(x) == 25

        # multiple filters
        x = noise |>
            lowpass(9Hz) |>
            mix(signal(sin,ω=12Hz)) |>
            highpass(4Hz,method=Chebyshev1(5,1)) |>
            sink

        y = noise |>
            lowpass(9Hz) |>
            mix(signal(sin,ω=12Hz)) |>
            sink |>
            highpass(4Hz,method=Chebyshev1(5,1)) |>
            sink
        @test x ≈ y

        y = noise |>
            lowpass(9Hz,blocksize=11) |>
            mix(signal(sin,ω=12Hz)) |>
            highpass(4Hz,method=Chebyshev1(5,1),blocksize=9) |>
            sink
        @test x ≈ y

        # multiple after and until commands
        x = signal(sin,ω=5Hz) |> after(2s) |> until(20s) |> after(2s) |>
            until(15s) |> after(2s) |> after(2s) |> until(5s) |> until(2s) |>
            sink(samplerate=12Hz)
        @test duration(x) == 2

        # multiple operators with a mix in the middle
        x = randn |> until(4s) |> after(50ms) |> lowpass(5Hz) |>
            mix(signal(sin,ω=7Hz)) |>
            until(3.5s) |>
            highpass(2Hz) |>
            append(rand(10,2)) |>
            append(rand(5,2)) |>
            sink(samplerate=20Hz)
        @test duration(x) == 4.25
    end
    next!(progress)

    @testset "README Examples" begin
        randn |> until(2s) |> normpower |> sink(example_wav,samplerate=44.1kHz)

        sound1 = signal(sin,ω=1kHz) |> until(5s) |> ramp |> normpower |>
            amplify(-20dB)
        result = sound1 |> sink(samplerate=4kHz)
        @test result |> nsamples == 4000*5
        @test mean(abs,result) > 0

        sound2 = example_wav |> normpower |> amplify(-20dB)

        # a 1kHz sawtooth wave
        sound3 = signal(ϕ -> ϕ/π - 1,ω=1kHz) |> until(2s) |> ramp |>
            normpower |> amplify(-20dB)

        # a 5 Hz amplitude modulated noise
        sound4 = randn |>
            amplify(signal(ϕ -> 0.5sin(ϕ) + 0.5,ω=5Hz)) |>
            until(5s) |> normpower |> amplify(-20dB)

        # a 1kHz tone surrounded by a notch noise
        SNR = 5dB
        x = signal(sin,ω=1kHz) |> until(1s) |> ramp |> normpower |> amplify(-20dB + SNR)
        y = signal(randn) |> until(1s) |> bandstop(0.5kHz,2kHz) |> normpower |>
            amplify(-20dB)
        scene = mix(x,y)

        # write all of the signal to a single file, at 44.1 kHz
        append(sound1,sound2,sound3,sound4,scene) |> sink(examples_wav)

        @test isfile(examples_wav)
    end
    next!(progress)

    for file in test_files
        isfile(file) && rm(file)
    end
end
