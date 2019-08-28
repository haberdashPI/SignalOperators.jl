using SignalOperators
using SignalOperators.Units
using Test

using SignalOperators: SignalTrait, IsSignal

# TODO: last stopped, need to specify eltype for SignalFunction

@testset "SignalOperators.jl" begin

    @testset "Unit Conversions" begin
        @test SignalOperators.inframes(1s,44.1kHz) == 44100
        @test SignalOperators.inframes(1.0s,44.1kHz) isa Float64
        @test SignalOperators.inseconds(50ms) == 1//20
        @test SignalOperators.inseconds(10frames,10Hz) == 1
        @test SignalOperators.inseconds(1s,44.1kHz) == 1
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
        @test SignalTrait(signal("test.wav")) isa IsSignal
        @test SignalTrait(signal(1,10Hz)) isa IsSignal
        @test SignalTrait(signal(sin,10Hz)) isa IsSignal
    end

    @testset "Cutting Operators" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s)
        @test !infsignal(tone)
        @test nsamples(tone) == 44100*5

        aftered = tone |> after(2s) 
        @test nsamples(aftered) == 44100*3
    end

    @testset "Convert to arrays" begin
        tone = signal(sin,44.1kHz,ω=100Hz) |> until(5s) |> Array
        @test tone[1] .< tone[110] # verify bump of sine wave
    end

    @testset "Padding" begin
        # TODO: the length of the signal is being incorrently computed
        # (is 500, should be 700)
        tone = signal(sin,100Hz,ω=10Hz) |> until(5s) |> pad(zero) |> 
            until(7s) |> Array
        @test mean(abs.(tone[0:50])) > 0
        @test mean(abs.(tone[51:70])) == 0
    end
        
    @testset "Appending" begin
        a = signal(sin,100Hz,ω=10Hz) |> until(5s)
        b = signal(sin,50Hz,ω=10Hz) |> until(5s)
        tones = a |> append(b) |> Array
        # TODO: create a test for this
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
