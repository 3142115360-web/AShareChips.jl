using AShareCostDistributions, Documenter

DocMeta.setdocmeta!(AShareCostDistributions, :DocTestSetup,
    :(using AShareCostDistributions); recursive=true)
makedocs(
    modules=[AShareCostDistributions],
    sitename="AShareCostDistributions.jl",
    authors="Zhao.Ruihong",
    repo="https://github.com/3142115360-web/AShareCostDistributions.jl/blob/{commit}{path}#{line}",
    checkdocs=:exports,
    doctest=true,
    format=Documenter.HTML(prettyurls=true, edit_link=nothing,
        canonical="https://3142115360-web.github.io/AShareCostDistributions.jl/",
        repolink="https://github.com/3142115360-web/AShareCostDistributions.jl",
        size_threshold=400_000),
    pages=[
        "Getting started" => "index.md",
        "Model" => "model.md",
        "Data and corporate actions" => "assumptions.md",
        "Importing daily data" => "data.md",
        "Validation and comparisons" => "validation.md",
        "Reference distributions" => "reference.md",
        "Adjustment events" => "adjustments.md",
        "File workflow" => "workflow.md",
        "Metric-summary comparisons" => "metric_comparison.md",
        "Public-market comparison" => "market_validation.md",
        "Performance" => "performance.md",
        "API" => "api.md",
    ],
)
