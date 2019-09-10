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
        # TODO: verify working `maybseconds` method
        # TODO: verify missing unit conversions
        # inHz(T <: Integer,x)
        # inframes(T,Number)

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
        @test ismissing(SignalOperators.inHz(missing))

        @test SignalOperators.inseconds(50ms) == 1//20
        @test SignalOperators.inseconds(50ms,10Hz) == 1//20
        @test SignalOperators.inseconds(10frames,10Hz) == 1
        @test SignalOperators.inseconds(1s,44.1kHz) == 1
        @test SignalOperators.inseconds(1,44.1kHz) == 1
        @test SignalOperators.inseconds(1) == 1
        @test ismissing(SignalOperators.inseconds(missing)) 


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

        # TOOD: padding is not properly defining the length of the child (or
        # drop is not properly defining the length to its child) TOOD:
        # addchannel seems to be making the signal "infinite" TODO: for some
        # reason `uniform` removes the itrapply signal TODO: tosamplerate is
        # being called and it's wrong (fix that) but it shouldn't be called

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
        # TODO: test that multiple blocks work

        # TODO: test proper filtering when using `after` (which should
        # require filtering the earlier part of the signal)

        # TODO: when I add test for filter blocking: make sure to include a case
        # where the first offset is not the first sample of a block 

        # TODO: add tests for custom filters (functions and predifined DSP 
        # filters)

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

        # TODO: add test for ramps defines solely by a function (rampon,
        # rampoff, and fadeto)
    end

    @testset "Resmapling" begin
        tone = signal(sin,20Hz,ω=5Hz) |> until(5s)
        resamp = tosamplerate(tone,40Hz)
        @test samplerate(resamp) == 40
        @test nsamples(resamp) == 2nsamples(tone)
        
        toned = tone |> sink
        resamp = tosamplerate(toned,40Hz)
        @test samplerate(resamp) == 40

        resampled = resamp |> sink
        @test size(resampled,1) == 2nsamples(tone)

        padded = tone |> pad(one) |> until(7s)
        resamp = tosamplerate(padded,40Hz)
        @test nsamples(resamp) == 7*40
        @test resamp |> sink |> size == (7*40,1)
        # verify that the state of the filter is proplery reset
        # (so it should produce same output a second time)
        resampled2 = resamp |> sink
        @test resampled ≈ resampled2


        # TODO: add tests that include resampling a filtered signal
        # and resampling an already resampled signal (which should not
        # resample twice unless there is an intervening data signal

        # TODO: add test to verify no-op for sample rate resampling
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

    @testset "Handling of arrays" begin
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

    # TODO: add a test to check handling of dB units

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
