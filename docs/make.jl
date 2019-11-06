using Documenter, SignalOperators

makedocs(;
    modules=[SignalOperators],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
        "Manual" => "manual.md",
        "Custom Signals" => "custom.md"
        "Reference" => "reference.md"
    ],
    repo="https://github.com/haberdashPI/SignalOperators.jl/blob/{commit}{path}#L{line}",
    sitename="SignalOperators.jl",
    authors="David Little",
)

deploydocs(;
    repo="github.com/haberdashPI/SignalOperators.jl",
)
