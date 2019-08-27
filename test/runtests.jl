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

end
