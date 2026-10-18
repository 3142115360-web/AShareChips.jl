using AShareChips, Documenter

DocMeta.setdocmeta!(AShareChips, :DocTestSetup, :(using AShareChips); recursive=true)
makedocs(
    modules=[AShareChips],
    sitename="AShareChips.jl",
    authors="AShareChips.jl contributors",
    remotes=nothing,
    checkdocs=:exports,
    doctest=true,
    format=Documenter.HTML(prettyurls=true, edit_link=nothing,
        repolink="https://github.com/3142115360-web/AShareChips.jl", size_threshold=400_000),
    pages=[
        "开始使用" => "index.md",
        "数学模型" => "model.md",
        "数据与除权" => "assumptions.md",
        "导入行情文件" => "data.md",
        "精度与对照" => "validation.md",
        "参考筹码文件" => "reference.md",
        "除权事件文件" => "adjustments.md",
        "文件对照流程" => "workflow.md",
        "指标摘要对照" => "metric_comparison.md",
        "真实行情模型对照" => "market_validation.md",
        "人工审查地图" => "review.md",
        "计算性能" => "performance.md",
        "API" => "api.md",
        "生态核查" => "ecosystem.md",
        "注册准备" => "registration.md",
        "注册名称与质量检查" => "quality.md",
    ],
)
