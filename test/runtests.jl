using SignalOperators
using SignalOperators.Units
using DSP
using LambdaFn
using Test
using Statistics
using WAV
using AxisArrays

using SignalOperators: SignalTrait, IsSignal

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

        @test_throws ErrorException SignalOperators.inframes(10s)

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
        @test SignalOperators.inradians(15frames) == 15
        @test SignalOperators.inradians(180°) ≈ π
        @test_throws ErrorException SignalOperators.inseconds(2frames)
    end

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

    @testset "Basic signals" begin
        @test SignalTrait(signal([1,2,3,4],10Hz)) isa IsSignal
        @test SignalTrait(signal(1:100,10Hz)) isa IsSignal
        @test SignalTrait(signal(1,10Hz)) isa IsSignal
        @test SignalTrait(signal(sin,10Hz)) isa IsSignal
        @test SignalTrait(signal(randn,10Hz)) isa IsSignal
        @test_throws ErrorException signal(x -> [1,2],5Hz) 
        noise = signal(randn,44.1kHz) |> until(5s) 
        @test isapprox(noise |> sink |> mean,0,atol=1e-2)
        z = zero(noise) |> until(5s)
        @test all(z |> sink .== 0)
        o = one(noise) |> until(5s)
        @test all(o |> sink .== 1)
    end

    @testset "Sink to arrays" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s) |> sink
        @test tone[1] .< tone[110] # verify bump of sine wave
    end

    @testset "Files as signals" begin
        tone = signal(range(0,1,length=4),10Hz) |> sink("test.wav")
        @test SignalTrait(signal("test.wav")) isa IsSignal
        @test isapprox(signal("test.wav"), range(0,1,length=4),rtol=1e-6)
    end

    @testset "Cutting Operators" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s)
        @test !infsignal(tone)
        @test nsamples(tone) == 44100*5

        x = rand(12)
        cutarray = signal(x,6Hz) |> after(0.5s) |> until(1s)
        @test nsamples(cutarray) == 6
        cutarray = signal(x,6Hz) |> until(1s) |> after(0.5s) 
        @test nsamples(cutarray) == 3
        cutarray = signal(x,6Hz) |> until(1s) |> until(0.5s) 
        cutarray2 = signal(x,6Hz) |> until(0.5s) 
        @test sink(cutarray) == sink(cutarray2)

        aftered = tone |> after(2s) 
        @test nsamples(aftered) == 44100*3
    end

    @testset "Padding" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) |> pad(zero) |> 
            until(7s) |> sink
        @test mean(abs.(tone[1:500])) > 0
        @test mean(abs.(tone[501:700])) == 0

        tone = signal(sin,100Hz,ω=10Hz) |> until(5s)
        tone2 = addchannel(tone,tone) |> pad(zero) |> until(7s) |> sink
        @test mean(abs.(tone2[1:500,:])) > 0
        @test mean(abs.(tone2[501:700,:])) == 0

        tone3 = addchannel(tone,tone,tone) |> pad(zero) |> until(7s) |> sink
        @test mean(abs.(tone3[1:500,:])) > 0
        @test mean(abs.(tone3[501:700,:])) == 0

        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) |> pad(0) |> 
            until(7s) |> sink
        @test mean(abs.(tone[1:500])) > 0
        @test mean(abs.(tone[501:700])) == 0
    end
        
    @testset "Appending" begin
        a = signal(sin,100Hz,ω=10Hz) |> until(5s)
        b = signal(sin,100Hz,ω=5Hz) |> until(5s)
        tones = a |> append(b)
        @test duration(tones) == 10
        @test length(sink(tones)) == 1000
    end

    @testset "Mixing" begin
        a = signal(sin,100Hz,ω=10Hz) |> until(5s)
        b = signal(sin,100Hz,ω=5Hz) |> until(5s)
        complex = mix(a,b)
        @test duration(complex) == 5
        @test length(sink(complex)) == 500
    end 

    @testset "Filtering" begin
        a = signal(sin,100Hz,ω=10Hz) |> until(5s)
        b = signal(sin,100Hz,ω=5Hz) |> until(5s)
        cmplx = mix(a,b)
        high = cmplx |> highpass(8Hz,method=Chebyshev1(5,1)) |> sink
        low = cmplx |> lowpass(6Hz,method=Butterworth(5)) |> sink
        highlow = low |>  highpass(8Hz,method=Chebyshev1(5,1)) |> sink
        bandp1 = cmplx |> bandpass(20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
        bandp2 = cmplx |> bandpass(2Hz,12Hz,method=Chebyshev1(5,1)) |> sink
        bands1 = cmplx |> bandstop(20Hz,30Hz,method=Chebyshev1(5,1)) |> sink
        bands2 = cmplx |> bandstop(2Hz,12Hz,method=Chebyshev1(5,1)) |> sink

        @test length(high) == 500
        @test length(low) == 500
        @test length(highlow) == 500
        @test mean(high) < 0.01
        @test mean(low) < 0.02
        @test 10mean(abs,highlow) < mean(abs,low)
        @test 10mean(abs,highlow) < mean(abs,high)
        @test 10mean(abs,bandp1) < mean(abs,bandp2)
        @test 10mean(abs,bands2) < mean(abs,bands1)

        @test mean(abs,cmplx |> amplify(10) |> normpower |> sink) < 
            mean(abs,cmplx |> amplify(10) |> sink)

        # proper filtering of blocks
        high2 = cmplx |> highpass(8Hz,method=Chebyshev1(5,1),blocksize=100)
        @test high2.blocksize == 100
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

    @testset "Ramps" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) 
        ramped = signal(sin,100Hz,ω=10Hz) |> until(5s) |> ramp(100ms) |> sink
        @test mean(abs,ramped[1:5]) < mean(abs,ramped[6:10])
        @test mean(abs,ramped) < mean(abs,sink(tone))
        @test mean(ramped) < 1e-4

        x = signal(sin,100Hz,ω=10Hz) |> until(5s)
        y = signal(sin,100Hz,ω=5Hz) |> until(5s)
        fading = fadeto(x,y,100ms)
        @test nsamples(fading) == (5+5-0.1)*100

        ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> until(100ms) |> 
            ramp(identity) |> sink
        @test mean(abs,ramped2[1:5]) < mean(abs,ramped2[6:10])
        ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> until(100ms) |> 
            rampon(identity) |> sink
        @test mean(abs,ramped2[1:5]) < mean(abs,ramped2[6:10])
        ramped2 = signal(sin,500Hz,ω=20Hz,ϕ=π/2) |> until(100ms) |> 
            rampoff(identity) |> sink
        @test mean(abs,ramped2[7:10]) < mean(abs,ramped2[1:6])
    end

    @testset "Resampling" begin
        tone = signal(sin,20Hz,ω=5Hz) |> until(5s)
        resamp = tosamplerate(tone,40Hz)
        @test samplerate(resamp) == 40
        @test nsamples(resamp) == 2nsamples(tone)
        
        toned = tone |> sink
        resamp = tosamplerate(toned,40Hz)
        @test samplerate(resamp) == 40

        resampled = resamp |> sink
        @test size(resampled,1) == 2nsamples(tone)

        # verify that the state of the filter is proplery reset
        # (so it should produce same output a second time)
        resampled2 = resamp |> sink
        @test resampled ≈ resampled2

        padded = tone |> pad(one) |> until(7s)
        resamp = tosamplerate(padded,40Hz)
        @test nsamples(resamp) == 7*40
        @test resamp |> sink |> size == (7*40,1)

        @test tosamplerate(tone,20Hz) === tone

        a = signal(sin,100Hz,ω=10Hz) |> until(5s)
        b = signal(sin,100Hz,ω=5Hz) |> until(5s)
        cmplx = mix(a,b)
        high = cmplx |> highpass(8Hz,method=Chebyshev1(5,1)) 
        resamp_high = tosamplerate(high,50Hz)
        @test resamp_high |> sink |> size == (250,1)

        resamp_twice = tosamplerate(toned,15Hz) |> tosamplerate(50Hz)
        @test resamp_twice isa SignalOperators.TakeApply
        @test resamp_twice.signal isa SignalOperators.FilteredSignal
        @test resamp_twice.signal.x isa SignalOperators.PaddedSignal
    end

    @testset "Change channel Count" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s)
        n = tone |> tochannels(2) |> nchannels
        @test n==2
        data = tone |> tochannels(2) |> sink
        @test size(data,2) == 2
        data2 = signal(data,100Hz) |> tochannels(1) |> sink
        @test size(data2,2) == 1

        @test_throws ErrorException tone |> tochannels(2) |> tochannels(3)
    end

    @testset "Automatic reformatting" begin
        a = signal(sin,200Hz,ω=10Hz) |> until(5s) |> tochannels(2)
        b = signal(sin,100Hz,ω=5Hz) |> until(3s)
        complex = mix(a,b)
        @test nchannels(complex) == 2
        @test samplerate(complex) == 200
        @test size(complex |> sink,1) == 1000
        more = mix(a,b,1)
        @test size(more |> sink,1) == 1000
    end

    @testset "Axis Arrays" begin
        x = AxisArray(ones(20),Axis{:time}(range(0s,2s,length=20)))
        proc = signal(x) |> ramp |> sink
    end


    @testset "Operating over empty signals" begin
        tone = signal(sin,200Hz,ω=10Hz) |> until(10frames) |> until(0frames)
        @test nsamples(tone) == 0
        @test mapsignal(-,tone) |> nsamples == 0
    end

    @testset "Handling of arrays/numbers" begin
        stereo = signal([10.0.*(1:10) 5.0.*(1:10)],5Hz)
        @test stereo |> nchannels == 2
        @test stereo |> sink |> size == (10,2)
        @test stereo |> until(5frames) |> sink |> size == (5,2)
        @test stereo |> after(5frames) |> sink |> size == (5,2)
        
        # Numbers
        tone = signal(sin,200Hz,ω=10Hz) |> mix(1.5) |> until(5s) |> sink
        @test all(tone .>= 0.5)
        samples = signal(1,5Hz) |> until(5s) |> sink
        @test samples isa AbstractArray{Int}

        dc_off = signal(1,10Hz) |> until(1s) |> amplify(20dB) |> sink
        @test all(dc_off .== 10)
        dc_off = signal(1,10Hz) |> until(1s) |> amplify(40dB) |> sink
        @test all(dc_off .== 100)

        # AbstractArrays
        tone = signal(sin,200Hz,ω=10Hz) |> mix(10.0.*(1:10)) |> sink
        @test all(tone[1:10] .>= 10.0*(1:10))
        samples = signal(10.0.*(1:10),5Hz) |> until(1s) |> sink
        @test samples isa AbstractArray{Float64}
        @test signal(10.0.*(1:10),5Hz) |> SignalOperators.channel_eltype == 
            Float64
    end

    @testset "Handling of padded mix and amplify" begin
        fs = 3Hz
        a = signal(2,fs) |> until(2s) |> append(signal(3,fs)) |> until(4s)
        b = signal(3,fs) |> until(3s) 

        result = mix(a,b) |> sink
        @test all(result .== [
            fill(2,3*2) .+ fill(3,3*2);
            fill(3,3*1) .+ fill(3,3*1);
            fill(3,3*1)
        ])

        result = amplify(a,b) |> sink
        @test all(result .== [
            fill(2,3*2) .* fill(3,3*2);
            fill(3,3*1) .* fill(3,3*1);
            fill(3,3*1)
        ])
    end

    @testset "Handling of infinite signals" begin
        tone = signal(sin,200Hz,ω=10Hz) |> until(10frames) |> after(5frames) |> 
            after(2frames)
        @test nsamples(tone) == 3
        @test size(sink(tone)) == (3,1)

        tone = signal(sin,200Hz,ω=10Hz) |> after(5frames) |> until(5frames)
        @test nsamples(tone) == 5
        @test size(sink(tone)) == (5,1)
        @test sink(tone)[1] > 0.9

        tone = signal(sin,200Hz,ω=10Hz) |> until(10frames) |> after(5frames)
        @test nsamples(tone) == 5
        @test size(sink(tone)) == (5,1)
        @test sink(tone)[1] > 0.9

        @test_throws ErrorException signal(sin,200Hz) |> sink
    end

    # TODO: add tests to check flexible handling of missing sample rates
    # TODO: add tests to check flexible handling of non-signals
end
