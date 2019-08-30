using SignalOperators
using SignalOperators.Units
using DSP
using LambdaFn
using Test
using Statistics
using WAV

using SignalOperators: SignalTrait, IsSignal

# TODO: last stopped, need to specify eltype for SignalFunction

@testset "SignalOperators.jl" begin

    @testset "Unit Conversions" begin
        @test SignalOperators.inframes(1s,44.1kHz) == 44100
        @test SignalOperators.inframes(Int,0.5s,44.1kHz) == 22050
        @test SignalOperators.inframes(Int,5frames) == 5
        @test SignalOperators.inframes(Int,5) == 5
        @test SignalOperators.inframes(1.0s,44.1kHz) isa Float64
        @test ismissing(SignalOperators.inframes(missing))
        @test ismissing(SignalOperators.inframes(Int,missing))
        @test ismissing(SignalOperators.inframes(Int,missing,5))

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
        z = signal(zero,noise) |> until(5s)
        @test all(z |> sink .== 0)
        o = signal(one,noise) |> until(5s)
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

        x = rand(6)
        cutarray = signal(x,6Hz) |> after(0.25s) |> until(0.5s)
        @test nsamples(cutarray) == 3
        cutarray = signal(x,6Hz) |> until(0.5s) |> after(0.25s) 
        @test nsamples(cutarray) == 1
        cutarray = signal(x,6Hz) |> until(0.5s) |> until(0.25s) 
        cutarray2 = signal(x,6Hz) |> until(0.25s) 
        @test sink(cutarray) == sink(cutarray2)

        aftered = tone |> after(2s) 
        @test nsamples(aftered) == 44100*3
    end

    @testset "Padding" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) |> pad(zero) |> 
            until(7s) |> sink
        @test mean(abs.(tone[1:500])) > 0
        @test mean(abs.(tone[501:700])) == 0
    end
        
    @testset "Appending" begin
        # TODO: append iterator type isn't yet work
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
    end

    @testset "Ramps" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) 
        ramped = signal(sin,100Hz,ω=10Hz) |> until(5s) |> ramp(100ms) |> sink
        @test mean(abs,ramped[1:5]) < mean(abs,ramped[6:10])
        @test mean(abs,ramped) < mean(abs,sink(tone))
        @test mean(ramped) < 1e-4

        # TODO: test fadeto
    end

    @testset "Resmapling" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s)
        resamp = tosamplerate(tone,500Hz)
        @test samplerate(resamp) == 500
    end

    @testset "Change channel Count" begin
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s)
        n = tone |> tochannels(2) |> nchannels
        @test n==2
        data = tone |> tochannels(2) |> sink
        @test size(data,2) == 2
        data2 = signal(data,100Hz) |> tochannels(1) |> sink
        @test size(data2,2) == 1
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

    @testset "Handling of non-sigals" begin
        # AbstractArrays
        tone = signal(sin,200Hz,ω=10Hz) |> mix(10.0.*(1:10)) |> sink
        @test all(tone[1:10] .>= 10.0*(1:10))
        samples = signal(10.0.*(1:10),5Hz) |> until(1s) |> collect
        @test samples isa Array{Tuple{Float64}}
        @test signal(10.0.*(1:10),5Hz) |> SignalOperators.signal_eltype == 
            Tuple{Float64}

        stereo = signal([10.0.*(1:10) 5.0.*(1:10)],5Hz)
        @test stereo |> nchannels == 2
        @test stereo |> sink |> size == (10,2)
        
        # Numbers
        tone = signal(sin,200Hz,ω=10Hz) |> mix(1.5) |> until(5s) |> sink
        @test all(tone .>= 0.5)
        samples = signal(1,5Hz) |> until(5s) |> collect
        @test samples isa Array{Tuple{Int}}
    end
end
