using SignalOperators
using Test
using Unitful: s,ms,Hz,kHz

@testset "SignalOperators.jl" begin

    @testset "Unit Conversions" begin
        @test inframes(1s,44.1kHz) == 44100
        @test inframes(1.0s,44.1kHz) isa Float64
        @test inseconds(50ms) == s*1//20
        @test inseconds(1s,44.1kHz) == 1s
        @test_throws ErrorException inseconds(2frames)
    end

    @testset "Function Currying" begin
        @test isa(mix(x),Function)
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
        @test SignalOperators.SignalTrait(signal([1,2,3,4],10Hz)) isa IsSignal
        @test SignalOperators.SignalTrait(signal(1:100,10Hz)) isa IsSignal
        @test SignalOperators.SignalTrait(signal("test.wav")) isa IsSignal
        @test SignalOperators.SignalTrait(signal(1,10Hz)) isa IsSignal
        @test SignalOperators.SignalTrait(signal(sin,10Hz)) isa IsSignal
    end

    @testset "Cutting Operators" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s)
        @test !isinf(nsamples(tone))
        @test nsamples(tone) == 44100*5
        vals = asarray(tone)
        @test vals[1,:] .< vals[2205,:]

        aftered = tone |> after(2s) |> asarray
        @test nsamples(aftered) = 44100*3
    end

    ## TODO:
    # extending
    # filters
    # binaryop
    # ramps
    # reformatting
    # automatic reformatting
    # handling of non-signals
end
