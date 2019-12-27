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
using Pkg
using DimensionalData
using DimensionalData: X, Time

SignalOperators.set_array_backend!(AxisArray)

using DSP
dB = SignalOperators.Units.dB

test_wav = "test.wav"
example_wav = "example.wav"
example_ogg = "example.ogg"
examples_wav = "examples.wav"
test_files = [test_wav,example_wav,example_ogg,examples_wav]

const total_test_groups = 34
progress = Progress(total_test_groups,desc="Running tests...")

@testset "SignalOperators.jl" begin

    @testset "Unit Conversions" begin
        @test SignalOperators.inframes(1s,44.1kHz) == 44100
        @test SignalOperators.inframes(Int,0.5s,44.1kHz) == 22050
        @test SignalOperators.inframes(Int,5frames) == 5
        @test SignalOperators.inframes(Int,5) == 5
        @test SignalOperators.inframes(5) == 5
        @test SignalOperators.inframes(1.0s,44.1kHz) isa Float64
        @test ismissing(SignalOperators.inframes(missing))
        @test ismissing(SignalOperators.inframes(Int,missing))
        @test ismissing(SignalOperators.inframes(Int,missing,5))
        @test ismissing(SignalOperators.inframes(missing,5))
        @test ismissing(SignalOperators.inframes(10s))

        @test SignalOperators.inHz(10) === 10
        @test SignalOperators.inHz(10Hz) === 10
        @test SignalOperators.inHz(Float64,10Hz) === 10.0
        @test SignalOperators.inHz(Int,10.5Hz) === 10
        @test ismissing(SignalOperators.inHz(missing))

        @test SignalOperators.inseconds(50ms) == 1//20
        @test SignalOperators.inseconds(50ms,10Hz) == 1//20
        @test SignalOperators.inseconds(10frames,10Hz) == 1
        @test SignalOperators.inseconds(1s,44.1kHz) == 1
        @test SignalOperators.inseconds(1,44.1kHz) == 1
        @test SignalOperators.inseconds(1) == 1
        @test ismissing(SignalOperators.inseconds(missing))
        @test SignalOperators.maybeseconds(2) == 2s
        @test SignalOperators.maybeseconds(5frames) == 5frames


        @test SignalOperators.inradians(15) == 15
        @test_throws Unitful.DimensionError SignalOperators.inradians(15frames)
        @test SignalOperators.inradians(180°) ≈ π
        @test ismissing(SignalOperators.inseconds(2frames))
    end
    next!(progress)

    @testset "Function Currying" begin
        x = Signal(1,10Hz)
        @test isa(Mix(x),Function)
        @test isa(Amplify(x),Function)
        @test isa(Filt(Lowpass,200Hz,400Hz),Function)
        @test isa(Ramp(10ms),Function)
        @test isa(RampOn(10ms),Function)
        @test isa(RampOff(10ms),Function)
        @test isa(FadeTo(x),Function)
        @test isa(Amplify(20dB),Function)
        @test isa(AddChannel(x),Function)
        @test isa(SelectChannel(1),Function)
        @test isa(Filt(x -> x),Function)
    end
    next!(progress)

    @testset "Basic signals" begin
        @test SignalTrait(Signal([1,2,3,4],10Hz)) isa IsSignal
        @test SignalTrait(Signal(1:100,10Hz)) isa IsSignal
        @test SignalTrait(Signal(1,10Hz)) isa IsSignal
        @test SignalTrait(Signal(sin,10Hz)) isa IsSignal
        @test SignalTrait(Signal(randn,10Hz)) isa IsSignal
        @test_throws ErrorException Signal(x -> [1,2],5Hz)
        noise = Signal(randn,50Hz) |> Until(5s)
        @test isapprox(noise |> sink |> mean,0,atol=0.3)
        z = Signal(0,10Hz) |> Until(5s)
        @test all(z |> sink .== 0)
        o = Signal(1,10Hz) |> Until(5s)
        @test all(o |> sink .== 1)
        @test_throws ErrorException Signal(rand(5),10Hz) |> Signal(5Hz)
        @test_throws ErrorException Signal(randn,10Hz) |> Signal(5Hz)
        @test_throws ErrorException Signal(rand(5),10Hz) |> sink(duration=10frames)
        @test_throws ErrorException sink!(ones(10,2),ones(5,2))
    end
    next!(progress)

    @testset "Array tuple output" begin
        SignalOperators.set_array_backend!(Array)
        x = rand(10,2)
        @test Signal(x,10Hz) == (x,10)
        @test sink(Mix(Signal(x,10Hz),1)) == (x.+1,10)
        SignalOperators.set_array_backend!(AxisArray)
    end
    next!(progress)

    @testset "Function signals" begin
        @test sink(Signal(sin,ω=5Hz,ϕ=π),duration=1s,framerate=20Hz) ==
            sink(Signal(sin,ω=5Hz,ϕ=π*rad),duration=1s,framerate=20Hz)
        @test sink(Signal(sin,ω=5Hz,ϕ=π),duration=1s,framerate=20Hz) ==
            sink(Signal(sin,ω=5Hz,ϕ=100ms),duration=1s,framerate=20Hz)
        @test sink(Signal(sin,ω=5Hz,ϕ=π),duration=1s,framerate=20Hz) ==
            sink(Signal(sin,ω=5Hz,ϕ=180°),duration=1s,framerate=20Hz)
        @test sink(Signal(sin,ϕ=1s),duration=1s,framerate=20Hz) ≈
            sink(Signal(sin,ω=1Hz,ϕ=0),duration=1s,framerate=20Hz)
        @test_throws ErrorException sink(Signal(sin,ϕ=2π*rad),duration=1s,
            framerate=20Hz)

        @test Signal(identity,ω=2Hz,10Hz) |> sink(duration=10frames) |>
            duration == 1.0
    end
    next!(progress)

    @testset "Sink to arrays" begin
        tone = Signal(sin,44.1kHz,ω=100Hz) |> Until(5s) |> sink
        @test tone[1] .< tone[110] # verify bump of sine wave
    end
    next!(progress)

    @testset "Files as signals" begin
        tone = Signal(range(0,1,length=4),10Hz) |> sink(test_wav)
        @test SignalTrait(Signal(test_wav)) isa IsSignal
        @test isapprox(Signal(test_wav), range(0,1,length=4),rtol=1e-6)
    end
    next!(progress)

    @testset "Change channel Count" begin
        tone = Signal(sin,22Hz,ω=10Hz) |> Until(5s)
        @test (tone |> ToChannels(2) |> nchannels) == 2
        @test (tone |> ToChannels(1) |> nchannels) == 1
        data = tone |> ToChannels(2) |> sink
        @test size(data,2) == 2
        data2 = Signal(data,22Hz) |> ToChannels(1) |> sink
        @test all(data2 .== sum(data,dims=2))
        @test size(data2,2) == 1

        @test_throws ErrorException tone |> ToChannels(2) |> ToChannels(3)
    end
    next!(progress)

    @testset "Cutting Operators" begin
        for nch in 1:2
            tone = Signal(sin,44.1kHz,ω=100Hz) |> ToChannels(nch) |> Until(5s)
            @test !isinf(nframes(tone))
            @test nframes(tone) == 44100*5

            x = rand(12,nch)
            cutarray = Signal(x,6Hz) |> After(0.5s) |> Until(1s)
            @test nframes(cutarray) == 6
            cutarray = Signal(x,6Hz) |> Until(1s) |> After(0.5s)
            @test nframes(cutarray) == 3
            cutarray = Signal(x,6Hz) |> Until(1s) |> Until(0.5s)
            cutarray2 = Signal(x,6Hz) |> Until(0.5s)
            @test sink(cutarray) == sink(cutarray2)

            @test_throws ErrorException Signal(1:10,5Hz) |> After(3s) |> sink

            x = rand(12,nch) |> Signal(6Hz)
            @test Append(Until(x,1s),After(x,1s)) |> nframes == 12

            aftered = tone |> After(2s)
            @test nframes(aftered) == 44100*3
        end
    end
    next!(progress)

    @testset "Padding" begin
        for nch in 1:3
            tone = Signal(sin,22Hz,ω=10Hz) |> ToChannels(nch) |> Until(5s) |>
                Pad(zero) |> Until(7s) |> sink
            @test mean(abs.(tone[1:22*5,:])) > 0
            @test mean(abs.(tone[22*5:22*7,:])) == 0

            tone = Signal(sin,22Hz,ω=10Hz) |> Until(5s) |> Pad(0) |>
                Until(7s) |> sink
            @test mean(abs.(tone[1:22*5,:])) > 0
            @test mean(abs.(tone[22*5:22*7,:])) == 0

            @test rand(10,nch) |> Signal(10Hz) |> Pad(zero) |> After(15frames) |>
                Until(10frames) |> sink == zeros(10,nch)

            x = 5ones(5,nch)
            result = Pad(x,zero) |> Until(10frames) |> sink(framerate=10Hz)
            all(iszero,result[6:10,:])

            x = rand(10,nch) |> Signal(10Hz)
            result = Pad(x,cycle) |> Until(30frames) |> sink
            @test result == vcat(x,x,x)
            result = Pad(x,mirror) |> Until(30frames) |> sink
            @test result == vcat(x,reverse(x,dims=1),x)
            result = Pad(x,lastframe) |> Until(15frames) |> sink
            @test all(result[11:end,:] .== result[10:10,:])

            x = Signal(sin,10Hz) |> ToChannels(nch) |> Until(1s)
            @test_throws ErrorException Pad(x,cycle) |> sink
            @test_throws ErrorException Pad(x,mirror) |> sink
            result = Pad(x,lastframe) |> Until(15frames) |> sink
            @test all(result[11:end,:] .== result[10:10,:])
            padv = rand(nch)
            result = Pad(x,padv) |> Until(15frames) |> sink
            @test all(result[11:end,:] .== padv')

            @test_throws ErrorException sin |> Until(1s) |> Pad(mirror) |>
                Until(2s) |> sink(framerate=10Hz)
            @test_throws ErrorException sin |> Until(1s) |> Pad((a,b) -> a+b) |>
                Until(2s) |> sink(framerate=10Hz)
        end
    end
    next!(progress)

    @testset "Appending" begin
        for nch in 1:2
            a = Signal(sin,22Hz,ω=10Hz) |> ToChannels(nch) |> Until(5s)
            b = Signal(sin,22Hz,ω=5Hz) |> ToChannels(nch) |> Until(5s)
            tones = a |> Append(b)
            @test duration(tones) == 10
            @test nframes(sink(tones)) == 220
            @test all(sink(tones) .== vcat(sink(a),sink(b)))

            fs = 3
            a = Signal(2,fs) |> ToChannels(nch) |> Until(2s) |>
                Append(Signal(3,fs)) |> Until(4s)
            @test nframes(sink(a)) == 4*fs

            x = Append(
                    rand(10,nch) |> After(0.5s),
                    Signal(sin) |> ToChannels(nch) |> Until(0.5s)) |>
                ToFramerate(20Hz) |> sink
            @test duration(x) ≈ 0.5

            @test_throws ErrorException Append(sin,1:10)
            @test SignalTrait(Append(1:10,sin)) isa IsSignal
        end
    end
    next!(progress)

    @testset "Mixing" begin
        for nch in 1:2
            a = Signal(sin,30Hz,ω=10Hz) |> ToChannels(2) |> Until(2s)
            b = Signal(sin,30Hz,ω=5Hz) |> ToChannels(2) |> Until(2s)
            complex = Mix(a,b)
            @test duration(complex) == 2
            @test nframes(sink(complex)) == 60
        end

        x = rand(20,SignalOperators.MAX_CHANNEL_STACK+1)
        y = rand(20,SignalOperators.MAX_CHANNEL_STACK+1)
        @test (Mix(x,y) |> sink(framerate=20Hz)) == (x .+ y)

        x = rand(20,2)
        result = MapSignal(reverse,x,bychannel=false) |> sink(framerate=20Hz)
        @test result == [x[:,2] x[:,1]]
    end
    next!(progress)

    @testset "Handling of padded Mix and Amplify" begin
        for nch in 1:2
            fs = 3Hz
            a = Signal(2,fs) |> ToChannels(nch) |> Until(2s) |>
                Append(Signal(3,fs)) |> Until(4s)
            b = Signal(3,fs) |> ToChannels(nch) |> Until(3s)

            result = Mix(a,b) |> sink
            for ch in 1:nch
                @test all(result[:,ch] .== [
                    fill(2,3*2) .+ fill(3,3*2);
                    fill(3,3*1) .+ fill(3,3*1);
                    fill(3,3*1)
                ])
            end

            result = Amplify(a,b) |> sink
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
        Signal(x,10Hz) |> AddChannel(y) |> sink!(z)
        @test all(iszero,z[6:10,3:4])
    end
    next!(progress)

    @testset "Filtering" begin
        for nch in 1:2
            a = Signal(sin,100Hz,ω=10Hz) |> ToChannels(nch) |> Until(5s)
            b = Signal(sin,100Hz,ω=5Hz) |> ToChannels(nch) |> Until(5s)
            cmplx = Mix(a,b)
            high = cmplx |> Filt(Highpass,8Hz,method=Chebyshev1(5,1)) |> sink
            low = cmplx |> Filt(Lowpass,6Hz,method=Butterworth(5)) |> sink
            highlow = low |>  Filt(Highpass,8Hz,method=Chebyshev1(5,1)) |> sink
            bandp1 = cmplx |> Filt(Bandpass,20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
            bandp2 = cmplx |> Filt(Bandpass,2Hz,12Hz,method=Chebyshev1(5,1)) |> sink
            bands1 = cmplx |> Filt(Bandstop,20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
            bands2 = cmplx |> Filt(Bandstop,2Hz,12Hz,method=Chebyshev1(5,1)) |> sink

            @test_throws ErrorException Filt(a,Highpass,75Hz)
            @test_throws ErrorException Filt(a,Lowpass,75Hz)
            @test_throws ErrorException Filt(a,Bandpass,75Hz,80Hz)
            @test_throws ErrorException Filt(a,Bandstop,75Hz,80Hz)

            @test nframes(high) == 500
            @test nframes(low) == 500
            @test nframes(highlow) == 500
            @test mean(high) < 0.01
            @test mean(low) < 0.02
            @test 10mean(abs,highlow) < mean(abs,low)
            @test 10mean(abs,highlow) < mean(abs,high)
            @test 10mean(abs,bandp1) < mean(abs,bandp2)
            @test 10mean(abs,bands2) < mean(abs,bands1)

            @test mean(abs,cmplx |> Amplify(10) |> Normpower |> sink) <
                mean(abs,cmplx |> Amplify(10) |> sink)

            # proper filtering of blocks
            high2_ = cmplx |> Filt(Highpass,8Hz,method=Chebyshev1(5,1),blocksize=100)
            @test high2_.blocksize == 100
            high2 = high2_ |> sink
            @test sink(high2) ≈ sink(high)

            # proper state of cut filtered signal (with blocks)
            high3 = cmplx |>
                Filt(Highpass,8Hz,method=Chebyshev1(5,1),blocksize=64) |>
                After(1s)
            @test sink(high3) ≈ sink(high)[1s .. 5s]

            # custom filter interface
            high4 = cmplx |>
                Filt(digitalfilter(Highpass(8,fs=framerate(cmplx)),
                                        Chebyshev1(5,1)))
            @test sink(high) == sink(high4)
        end
    end
    next!(progress)

    @testset "Ramps" begin
        for nch in 1:2
            tone = Signal(sin,50Hz,ω=10Hz) |> ToChannels(nch) |> Until(5s)
            ramped = Signal(sin,50Hz,ω=10Hz) |> ToChannels(nch) |> Until(5s) |>
                Ramp(500ms) |> sink
            @test mean(@λ(_^2),ramped[0s .. 500ms]) < mean(@λ(_^2),ramped[500ms .. 1s])
            @test mean(@λ(_^2),ramped[4.5s .. 5s]) < mean(@λ(_^2),ramped[4s .. 4.5s])
            @test mean(abs,ramped) < mean(abs,sink(tone))
            @test mean(ramped) < 1e-4

            x = Signal(sin,22Hz,ω=10Hz) |> ToChannels(nch) |> Until(2s)
            y = Signal(sin,22Hz,ω=5Hz) |> ToChannels(nch) |> Until(2s)
            fading = FadeTo(x,y,500ms)
            result = sink(fading)
            @test nframes(fading) == ceil(Int,(2+2-0.5)*22)
            @test nframes(result) == nframes(fading)
            @test result[1:33,:] == sink(x)[1:33,:]
            @test result[44:end,:] == sink(y)[11:end,:]

            ramped2 = Signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> ToChannels(nch) |>
                Until(100ms) |> Ramp(identity) |> sink
            @test mean(abs,ramped2[1:5,:]) < mean(abs,ramped2[6:10,:])
            ramped2 = Signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> ToChannels(nch) |>
                Until(100ms) |> RampOn(identity) |> sink
            @test mean(abs,ramped2[1:5,:]) < mean(abs,ramped2[6:10,:])
            ramped2 = Signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> ToChannels(nch) |>
                Until(100ms) |> RampOff(identity) |> sink
            @test mean(abs,ramped2[7:10,:]) < mean(abs,ramped2[1:6,:])
        end
    end
    next!(progress)

    @testset "Resampling" begin
        for nch in 1:2
            tone = Signal(sin,20Hz,ω=5Hz) |> ToChannels(nch) |> Until(5s)
            resamp = ToFramerate(tone,40Hz)
            @test framerate(resamp) == 40
            @test nframes(resamp) == 2nframes(tone)

            downsamp = ToFramerate(tone,15Hz)
            @test framerate(downsamp) == 15
            @test nframes(downsamp) == 0.75nframes(tone)
            @test sink(downsamp) |> nframes == nframes(downsamp)

            x = rand(10,nch) |> ToFramerate(2kHz) |> sink
            @test framerate(x) == 2000

            toned = tone |> sink
            resamp = ToFramerate(toned,40Hz)
            @test framerate(resamp) == 40

            resampled = resamp |> sink
            @test nframes(resampled) == 2nframes(tone)

            # test multi-block resampling
            resamp = ToFramerate(toned,40Hz,blocksize=64)
            resampled2 = sink(resamp)
            @test nframes(resampled) == 2nframes(tone)
            @test resampled ≈ resampled2

            # verify that the state of the filter is proplery reset
            # (so it should produce same output a second time)
            resampled3 = resamp |> sink
            @test resampled2 ≈ resampled3

            padded = tone |> Pad(one) |> Until(7s)
            resamp = ToFramerate(padded,40Hz)
            @test nframes(resamp) == 7*40
            @test resamp |> sink |> size == (7*40,nch)

            @test ToFramerate(tone,20Hz) === tone

            a = Signal(sin,48Hz,ω=10Hz) |> ToChannels(nch) |> Until(3s)
            b = Signal(sin,48Hz,ω=5Hz) |> ToChannels(nch) |> Until(3s)
            cmplx = Mix(a,b)
            high = cmplx |> Filt(Highpass,8Hz,method=Chebyshev1(5,1))
            resamp_high = ToFramerate(high,24Hz)
            @test resamp_high |> sink |> size == (72,nch)

            resamp_twice = ToFramerate(toned,15Hz) |> ToFramerate(50Hz)
            @test resamp_twice isa SignalOperators.FilteredSignal
            @test SignalOperators.child(resamp_twice) === toned
        end
    end
    next!(progress)

    @testset "Automatic reformatting" begin
        a = Signal(sin,200Hz,ω=10Hz) |> ToChannels(2) |> Until(5s)
        b = Signal(sin,100Hz,ω=5Hz) |> Until(3s)
        complex = Mix(a,b)
        @test nchannels(complex) == 2
        @test framerate(complex) == 200
        @test nframes(complex |> sink) == 1000
        more = Mix(a,b,1)
        @test nframes(more |> sink) == 1000
    end
    next!(progress)

    @testset "Axis Arrays" begin
        x = AxisArray(ones(20),Axis{:time}(range(0s,2s,length=20)))
        proc = Signal(x) |> Ramp |> sink
        @test size(proc,1) == size(x,1)
        @test proc isa AxisArray
    end
    next!(progress)


    @testset "Operating over empty signals" begin
        for nch in 1:2
            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |>
                Until(10frames) |> Until(0frames)
            @test nframes(tone) == 0
            @test MapSignal(-,tone) |> nframes == 0
        end
    end
    next!(progress)

    @testset "Normpower" begin
        for nch in 1:2
            tone = Signal(sin,10Hz,ω=2Hz) |> ToChannels(nch) |> Until(2s) |>
                Ramp |> Normpower
            @test all(sqrt.(mean(sink(tone).^2,dims=1)) .≈ 1)

            resamp = tone |> ToFramerate(20Hz) |> sink
            @test all(sqrt.(mean(sink(resamp).^2,dims=1)) .≈ 1)
        end
    end
    next!(progress)

    @testset "Handling of arrays/numbers" begin
        stereo = Signal([10.0.*(1:10) 5.0.*(1:10)],5Hz)
        @test stereo |> nchannels == 2
        @test stereo |> sink |> size == (10,2)
        @test stereo |> Until(5frames) |> sink |> size == (5,2)
        @test stereo |> After(5frames) |> sink |> size == (5,2)

        for nch in 1:2
            # Numbers
            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |> Mix(1.5) |>
                Until(5s) |> sink
            @test all(tone .>= 0.5)
            x = Signal(1,5Hz) |> ToChannels(nch) |> Until(5s) |> sink
            @test x isa AbstractArray{Int}

            @test all(10 |> ToChannels(nch) |> Until(1s) |>
                sink(framerate=10Hz) .== 10)

            dc_off = Signal(1,10Hz) |> ToChannels(nch) |> Until(1s) |>
                Amplify(20dB) |> sink
            @test all(dc_off .== 10)
            dc_off = Signal(1,10Hz) |> ToChannels(nch) |> Until(1s) |>
                Amplify(40dB) |> sink
            @test all(dc_off .== 100)

            # AbstractArrays
            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |>
                Mix(10.0.*(1:10)) |> sink
            @test all(tone[1:10,:] .>= 10.0*(1:10))
            x = Signal(10.0.*(1:10),5Hz) |> ToChannels(nch) |> Until(1s) |> sink
            @test x isa AbstractArray{Float64}
            @test Signal(10.0.*(1:10),5Hz) |> ToChannels(nch) |>
                SignalOperators.channel_eltype == Float64
        end

        # AxisArray
        x = AxisArray(rand(2,10),Axis{:channel}(1:2),
            Axis{:time}(range(0,1,length=10)))
        @test x |> Until(500ms) |> sink |> size == (4,2)

        # poorly shaped arrays
        @test_throws ErrorException Signal(rand(2,2,2))
    end
    next!(progress)

    @testset "Handling of infinite signals" begin
        for nch in 1:2
            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |>
                Until(10frames) |> After(5frames) |> After(2frames)
            @test nframes(tone) == 3
            @test size(sink(tone)) == (3,nch)

            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |>
                After(5frames) |> Until(5frames)
            @test nframes(tone) == 5
            @test size(sink(tone)) == (5,nch)
            @test sink(tone)[1] > 0.9

            tone = Signal(sin,200Hz,ω=10Hz) |> ToChannels(nch) |>
                Until(10frames) |> After(5frames)
            @test nframes(tone) == 5
            @test size(sink(tone)) == (5,nch)
            @test sink(tone)[1] > 0.9

            @test_throws ErrorException Signal(sin,200Hz) |> Normpower |> sink(duration=1s)

            @test_throws ErrorException Signal(sin,200Hz) |> ToChannels(nch) |>
                sink
        end
    end
    next!(progress)

    @testset "Test that non-signals correctly error" begin
        x = r"nonsignal"
        @test_throws MethodError x |> framerate
        @test_throws ErrorException x |> sink(framerate=10Hz)
        @test_throws MethodError x |> duration
        @test_throws ErrorException x |> Until(5s)
        @test_throws ErrorException x |> After(2s)
        @test_throws MethodError x |> nframes
        @test_throws MethodError x |> nchannels
        @test_throws ErrorException x |> Pad(zero)
        @test_throws MethodError x |> Filt(Lowpass,3Hz)
        @test_throws ErrorException x |> Normpower
        @test_throws ErrorException x |> SelectChannel(1)
        @test_throws ErrorException x |> Ramp

        x = rand(5,2)
        y = r"nonsignal"
        @test_throws ErrorException x |> Append(y)
        @test_throws ErrorException x |> Mix(y)
        @test_throws ErrorException x |> AddChannel(y)
        @test_throws ErrorException x |> FadeTo(y)
    end
    next!(progress)

    @testset "Handle of frame units" begin
        x = Signal(rand(100,2),10Hz)
        y = Signal(rand(50,2),10Hz)

        @test x |> Until(30frames) |> sink |> nframes == 30
        @test x |> After(30frames) |> sink |> nframes == 70
        @test x |> Append(y) |> After(20frames) |> sink |> nframes == 130
        @test x |> Append(y) |> Until(130frames) |> sink |> nframes == 130
        @test x |> Pad(zero) |> Until(150frames) |> sink |> nframes == 150

        @test x |> Ramp(10frames) |> sink |> nframes == 100
        @test x |> FadeTo(y,10frames) |> sink |> nframes > 100
    end
    next!(progress)

    function showstring(x)
        io = IOBuffer()
        show(io,MIME("text/plain"),x)
        String(take!(io))
    end

    @testset "Handle printing" begin
        x = Signal(rand(100,2),10Hz)
        y = Signal(rand(50,2),10Hz)
        @test Signal(sin,22Hz,ω=10Hz,ϕ=π/4) |> showstring ==
            "Signal(sin,ω=10,ϕ=0.125π) (22.0 Hz)"
        @test Signal(2dB,10Hz) |> showstring ==
            "2.0000000000000004 dB (10.0 Hz)"
        @test x |> Until(5s) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Until(5 s)"
        @test x |> After(2s) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> After(2 s)"
        @test x |> Append(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    Append(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> Pad(zero) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Pad(zero)"
        @test x |> Filt(Lowpass,3Hz) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Filt(Lowpass,3 Hz)"
        @test x |> Normpower |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Normpower"
        @test x |> Mix(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Mix(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> Amplify(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    Amplify(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> AddChannel(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    AddChannel(50×2 Array{Float64,2}: … (10.0 Hz))"
        @test x |> SelectChannel(1) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> SelectChannel(1)"
        @test MapSignal(identity,x) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> MapSignal(identity,)"
        @test x |> ToFramerate(20Hz) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> ToFramerate(20 Hz)"
        @test x |> ToChannels(1) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> ToChannels(1)"
        @test x[:,1] |> ToChannels(2) |> showstring ==
            "100-element Array{Float64,1}: … (10.0 Hz) |> ToChannels(2)"
        @test startswith(rand(5,2) |> Filt(fs -> Highpass(10,20,fs=fs)) |> showstring,
            "5×2 Array{Float64,2}: … |> Filt(")

        @test x |> Ramp |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    Amplify(RampOnFn(10 ms)) |> Amplify(RampOffFn(10 ms))"
        @test x |> Ramp(identity) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |>\n    Amplify(RampOnFn(10 ms,identity)) |> Amplify(RampOffFn(10 ms,identity))"
        @test x |> FadeTo(y) |> showstring ==
            "100×2 Array{Float64,2}: … (10.0 Hz) |> Amplify(RampOffFn(10 ms)) |>\n    Mix(0.0 (10.0 Hz) |> Until(100 frames) |>\n            ToChannels(2) |> Append(50×2 Array{Float64,2}: … (10.0 Hz) |>\n                                        Amplify(RampOnFn(10 ms))))"
    end
    next!(progress)

    @testset "Non-lazy operators" begin
        x = Signal(rand(10,2),10Hz)
        y = Signal(rand(10,2),10Hz)

        @test until(x,5frames) |> size == (5,2)
        @test after(x,5frames) |> size == (5,2)
        @test append(x,y) |> size == (20,2)
        @test prepend(x,y) |> size == (20,2)
        @test mapsignal(+,x,y) == x.+y
        @test mix(x,y) == x.+y
        @test amplify(x,y) == x.*y
        @test addchannel(x,y) |> size == (10,4)
        @test all(selectchannel(x,1) .== x[:,1])
        @test rampon(x) |> size == (10,2)
        @test rampoff(x) |> size == (10,2)
        @test ramp(x) |> size == (10,2)
        @test fadeto(x,y,4frames) |> size == (10+10-4,2)
        # @test toframerate(x,5Hz) |> size == (5,2)
        x_ = Signal(rand(40,2),20Hz)
        @test toframerate(x_,40Hz) |> size == (80,2)
        @test tochannels(x,1) |> size == (10,1)
        @test toeltype(x,Float32) |> eltype <: Float32
        # @test format(x,5Hz,1) |> size == (5,1)
        @test format(x_,40Hz,1) |> size == (80,1)
    end
    next!(progress)


    @testset "Handle lower bitrate" begin
        x = Signal(rand(Float32,100,2),10Hz)
        y = Signal(rand(Float32,50,2),10Hz)
        @test x |> framerate == 10
        @test x |> sink |> eltype == Float32
        @test x |> duration == 10
        @test x |> Until(5s) |> sink |> eltype == Float32
        @test x |> After(2s) |> sink |> eltype == Float32
        @test x |> nframes == 100
        @test x |> nchannels == 2
        @test x |> Append(y) |> sink |> eltype == Float32
        @test x |> Append(y) |> After(2s) |> sink |> eltype == Float32
        @test x |> Append(y) |> Until(13s) |> sink |> eltype == Float32
        @test x |> Pad(zero) |> Until(15s) |> sink |> eltype == Float32
        @test x |> Filt(Lowpass,3Hz) |> sink |> eltype == Float32
        @test x |> Normpower |> Amplify(-10f0*dB) |> sink |> eltype == Float32
        @test x |> Mix(y) |> sink(framerate=10Hz) |> eltype == Float32
        @test x |> AddChannel(y) |> sink(framerate=10Hz) |> eltype == Float32
        @test x |> SelectChannel(1) |> sink(framerate=10Hz) |> eltype == Float32
        @test x |> Ramp |> sink |> eltype == Float32

        @test x |> FadeTo(y) |> sink |> eltype == Float32
    end
    next!(progress)

    @testset "Handle fixed point numbers" begin
        x = Signal(rand(Fixed{Int16,15},100,2),10Hz)
        y = Signal(rand(Fixed{Int16,15},50,2),10Hz)
        @test x |> framerate == 10
        @test x |> sink |> framerate == 10
        @test x |> duration == 10
        @test x |> Until(5s) |> duration == 5
        @test x |> After(2s) |> duration == 8
        @test x |> nframes == 100
        @test x |> nchannels == 2
        @test x |> Until(3s) |> sink |> nframes == 30
        @test x |> After(3s) |> sink |> nframes == 70
        @test x |> Append(y) |> sink |> nframes == 150
        @test x |> Append(y) |> After(2s) |> sink |> nframes == 130
        @test x |> Append(y) |> Until(13s) |> sink |> nframes == 130
        @test x |> Pad(zero) |> Until(15s) |> sink |> nframes == 150
        @test x |> Filt(Lowpass,3Hz) |> sink |> nframes == 100
        @test x |> Normpower |> Amplify(-10dB) |> sink |> nframes == 100
        @test x |> Mix(y) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> AddChannel(y) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> SelectChannel(1) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> Ramp |> sink |> nframes == 100
        @test x |> FadeTo(y) |> sink |> nframes == 150
    end
    next!(progress)

    @testset "Handle unknown frame rates" begin
        x = rand(100,2)
        y = rand(50,2)
        @test x |> framerate |> ismissing
        @test x |> sink(framerate=10Hz) |> framerate == 10
        @test x |> ToFramerate(10Hz) |> framerate == 10
        @test x |> duration |> ismissing
        @test x |> Until(5s) |> duration |> ismissing
        @test x |> After(2s) |> duration |> ismissing
        @test x |> nframes == 100
        @test x |> nchannels == 2
        @test x |> sink(framerate=10Hz) |> framerate == 10
        @test x |> Until(3s) |> sink(framerate=10Hz) |> nframes == 30
        @test x |> After(3s) |> sink(framerate=10Hz) |> nframes == 70
        @test x |> Append(y) |> sink(framerate=10Hz) |> nframes == 150
        @test x |> Append(y) |> After(2s) |> sink(framerate=10Hz) |>
            nframes == 130
        @test x |> Append(y) |> Until(13s) |> sink(framerate=10Hz) |>
            nframes == 130
        @test x |> Pad(zero) |> Until(15s) |> sink(framerate=10Hz) |>
            nframes == 150
        @test x |> Filt(Lowpass,3Hz) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> Normpower |> Amplify(-10dB) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> Mix(y) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> AddChannel(y) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> SelectChannel(1) |> sink(framerate=10Hz) |> nframes == 100
        @test x |> Ramp |> sink(framerate=10Hz) |> nframes == 100

        @test_throws ErrorException x |> FadeTo(y) |> sink(framerate=10Hz)
    end
    next!(progress)

    @testset "Short-block Operators" begin
        x = Signal(ones(25,2),10Hz)
        y = Signal(ones(10,2),10Hz)
        z = Signal(ones(15,2),10Hz)
        @test sink(x |> Append(y) |> Append(z) |> Filt(Lowpass,3Hz,blocksize=5)) ==
            sink(x |> Append(y) |> Append(z) |> Filt(Lowpass,3Hz))

        @test sink(x |> Pad(zero) |> Until(15s) |> Append(y) |> Filt(Lowpass,3Hz,blocksize=5)) ==
            sink(x |> Pad(zero) |> Until(15s) |> Append(y) |> Filt(Lowpass,3Hz,blocksize=5))

        @test sink(x |> RampOn(7frames) |> Filt(Lowpass,3Hz,blocksize=5)) ==
            sink(x |> RampOn(7frames) |> Filt(Lowpass,3Hz))
        @test sink(x |> Ramp(3frames) |> Filt(Lowpass,3Hz,blocksize=5)) ==
            sink(x |> Ramp(3frames) |> Filt(Lowpass,3Hz))
    end

    # try out more complicated combinations of various features
    @testset "Stress tests" begin
        # Append, dropping the first signal entirely
        a = Until(sin,2s)
        b = Until(cos,2s)
        x = Append(a,b) |> After(3s)
        @test sink(x,framerate=20Hz) == b |> After(1s) |> sink(framerate=20Hz)

        noise = Signal(randn,20Hz) |> Until(6s) |> sink

        # filtering in combination with `After`
        x = noise |> Filt(Lowpass,7Hz) |> Until(4s)
        afterx = noise |> Filt(Lowpass,7Hz) |> Until(4s) |> After(2s)
        @test sink(x)[2s .. 4s] ≈ sink(afterx)

        # multiple frame rates
        x = Signal(sin,ω=10Hz,20Hz) |> Until(4s) |> sink |>
            ToFramerate(30Hz) |> Filt(Lowpass,10Hz) |> FadeTo(Signal(sin,ω=5Hz)) |>
            ToFramerate(20Hz)
        @test framerate(x) == 20

        x = Signal(sin,ω=10Hz,20Hz) |> Until(4s) |> sink |>
            ToFramerate(30Hz) |> Filt(Lowpass,10Hz) |> FadeTo(Signal(sin,ω=5Hz)) |>
            ToFramerate(25Hz) |> sink
        @test framerate(x) == 25

        # multiple filters
        x = noise |>
            Filt(Lowpass,9Hz) |>
            Mix(Signal(sin,ω=12Hz)) |>
            Filt(Highpass,4Hz,method=Chebyshev1(5,1)) |>
            sink

        y = noise |>
            Filt(Lowpass,9Hz) |>
            Mix(Signal(sin,ω=12Hz)) |>
            sink |>
            Filt(Highpass,4Hz,method=Chebyshev1(5,1)) |>
            sink
        @test x ≈ y

        y = noise |>
            Filt(Lowpass,9Hz,blocksize=11) |>
            Mix(Signal(sin,ω=12Hz)) |>
            Filt(Highpass,4Hz,method=Chebyshev1(5,1),blocksize=9) |>
            sink
        @test x ≈ y

        # multiple After and Until commands
        x = Signal(sin,ω=5Hz) |> After(2s) |> Until(20s) |> After(2s) |>
            Until(15s) |> After(2s) |> After(2s) |> Until(5s) |> Until(2s) |>
            sink(framerate=12Hz)
        @test duration(x) == 2

        # different offset appending summation
        x = Append(1 |> Until(1s),2 |> Until(2s))
        y = Append(3 |> Until(2s),4 |> Until(1s))
        result = Mix(x,y) |> sink(framerate=10Hz)
        @test all(result .== [fill(4,10);fill(5,10);fill(6,10)])

        # multiple operators with a Mix in the middle
        x = randn |> Until(4s) |> After(50ms) |> Filt(Lowpass,5Hz) |>
            Mix(Signal(sin,ω=7Hz)) |>
            Until(3.5s) |>
            Filt(Highpass,2Hz) |>
            Append(rand(10,2)) |>
            Append(rand(5,2)) |>
            sink(framerate=20Hz)
        @test duration(x) == 4.25
    end
    next!(progress)

    @testset "README Examples" begin
        randn |> Until(2s) |> Normpower |> sink(example_wav,framerate=44.1kHz)

        sound1 = Signal(sin,ω=1kHz) |> Until(5s) |> Ramp |> Normpower |>
            Amplify(-20dB)
        result = sound1 |> sink(framerate=4kHz)
        @test result |> nframes == 4000*5
        @test mean(abs,result) > 0

        sound2 = example_wav |> Normpower |> Amplify(-20dB)

        # a 1kHz sawtooth wave
        sound3 = Signal(ϕ -> ϕ/π - 1,ω=1kHz) |> Until(2s) |> Ramp |>
            Normpower |> Amplify(-20dB)

        # a 5 Hz amplitude modulated noise
        sound4 = randn |>
            Amplify(Signal(ϕ -> 0.5sin(ϕ) + 0.5,ω=5Hz)) |>
            Until(5s) |> Normpower |> Amplify(-20dB)

        # a 1kHz tone surrounded by a notch noise
        SNR = 5dB
        x = Signal(sin,ω=1kHz) |> Until(1s) |> Ramp |> Normpower |> Amplify(-20dB + SNR)
        y = Signal(randn) |> Until(1s) |> Filt(Bandstop,0.5kHz,2kHz) |> Normpower |>
            Amplify(-20dB)
        scene = Mix(x,y)

        # write all of the signal to a single file, at 44.1 kHz
        Append(sound1,sound2,sound3,sound4,scene) |> sink(examples_wav)

        @test isfile(examples_wav)
    end
    next!(progress)

    @testset "Testing DimensionalData" begin
        x = rand(10,2)
        data = DimensionalArray(x,(Time(range(0s,1s,length=10)),X(1:2)))
        @test all(sink(Mix(data,1)) .== data .+ 1)
        data2 = x |> Signal(10Hz) |> sink(DimensionalArray)
        @test data2 == data
        @test sink(Mix(data,1)) isa DimensionalArray
    end
    next!(progress)

    # test LibSndFile and SampleBuf
    # (only supported for Julia versions 1.3 or higher)
    @static if VERSION ≥ v"1.3"
        mydir = mktempdir(@__DIR__)
        Pkg.activate(mydir)
        Pkg.add("LibSndFile")
        Pkg.add("SampledSignals")
        @testset "Testing LibSndFile" begin
            using LibSndFile
            using SampledSignals: SampleBuf

            randn |> Until(2s) |> Normpower |> sink(example_ogg,framerate=4kHz)
            x = example_ogg |> sink(SampleBuf)
            example_ogg |> sink(AxisArray)
            @test SignalOperators.framerate(x) == 4000
            @test sink(Mix(x,1)) isa SampleBuf
        end
        next!(progress)

        @testset "Test adaptive return type" begin
            x = rand(10,2)

            data = DimensionalArray(x,(Time(range(0s,1s,length=10)),X(1:2)))
            @test sink(Mix(1,data)) isa DimensionalArray
            data = SampleBuf(x,10)
            @test sink(Mix(1,data)) isa SampleBuf

            SignalOperators.set_array_backend!(AxisArray)
            data = Signal(rand(10,2),10Hz)
            @test data isa AxisArray
            @test sink(Mix(1,data)) isa AxisArray

            SignalOperators.set_array_backend!(SampleBuf)
            @test Signal(rand(10,2),10Hz) isa SampleBuf
            SignalOperators.set_array_backend!(DimensionalArray)
            @test Signal(rand(10,2),10Hz) isa DimensionalArray

            SignalOperators.set_array_backend!(AxisArray)
            data = Signal(rand(10,2),10Hz)
            SignalOperators.set_array_backend!(Array)
            @test sink(Mix(rand(10,2),data)) isa AxisArray
            data2 = SampleBuf(x,10)
            @test sink(Mix(rand(10,2),data2)) isa SampleBuf
            @test sink(Mix(data,data2)) isa AxisArray
            @test sink(Mix(data2,data)) isa SampleBuf
        end
        rm(mydir,recursive=true,force=true)
        next!(progress)
    end

    for file in test_files
        isfile(file) && rm(file)
    end
end
