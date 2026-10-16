# AShareChips.jl

A 股筹码成本分布的可扩展 Julia 研究模型。将日成交成本分布与历史筹码按有效换手率混合，输出平均成本、获利比例、成本分位数、集中度和历史快照；估计成本分布，不还原账户真实持仓。

**本地开发版 `0.1.0`，尚未注册 General。** 支持 Julia 1.10 及以上的 1.x 版本；运行只依赖标准库 Dates，没有第三方运行依赖。测试使用 Aqua 质量检查。通达信等软件是对照目标，当前没有实测等价结论。

## 从行情文件开始

仓库自带一个明确标注为合成数据的表格，可直接试运行：

```julia
using Pkg
Pkg.activate(".")
using AShareChips

series = read_bars("examples/fixtures/daily_synthetic.csv";
    price_basis=:unadjusted, turnover_basis=:float_shares,
    turnover_unit=:percent)
grid = PriceGrid(collect(8.0:0.02:14.0))
chips = chip_distribution(series; grid)
average_cost(chips)
profit_ratio(chips, 11.0)             # 比例，不是百分数
cost_quantile(chips, 0.5)
concentration(chips; coverage=0.9)    # 等尾成本区间与相对宽度
```

简单无引号文件支持自定义表头、证券代码、日期格式和分隔符；拒绝乱序、重复日期、混合证券及无效数值。复杂 CSV 先用上游解析包处理，再构造 `BarSeries`。[导入说明](docs/src/data.md)解释单位与价格基准。

也可编辑 `examples/analysis.toml` 中的输入文件、口径和网格，生成逐日结果表；示例配置同时生成与手工合成参考的误差表：

```sh
julia --project=. examples/analyze_csv.jl examples/analysis.toml
```

结果包含日期、证券、平均成本、收盘价下的获利比例、成本分位数和区间宽度。脚本拒绝覆盖已有文件、目录或链接，并逐文件以临时文件安全发布；重新运行时请换输出文件名。[完整流程](docs/src/workflow.md)也支持导入明确的除权事件。

## 研究模型与对照

递推为 `C_t = (1-α_t) C_(t-1) + α_t D_t`。提供均匀、三角、逐笔量加权模型，以及线性/指数有效换手模型；可继承抽象类型替换。`chip_history` 返回历史状态；`dated_history` 同时保留日期。`compare_distributions` 比较不同网格的完整 CDF、Wasserstein 距离和指标偏差；`grid_convergence` 检查网格敏感性。`read_distributions` 导入参考直方图；`read_adjustments` 对齐事件；`compare_history` 按证券、日期和价格基准比较历史。

- 换手输入为比例：5% 写作 `0.05`；可超过 1。导入百分数时显式选 `:percent`。
- 无 prior 时以首日完整日成本分布初始化；已有分布用 `initial` 传入。
- 默认三角峰为 `(low+high+close)/3`；`:vwap` 要求供应已核实单位的 VWAP。
- 状态是每个 bin 内均匀的直方图，逐笔价格和一字板也有网格误差。
- 超出网格报错；成本坐标调整先于当天换手。固定复权的日期序列禁止再次做非 identity 调整。

[模型](docs/src/model.md) · [数据与除权](docs/src/assumptions.md) · [精度与对照](docs/src/validation.md) · [API](docs/src/api.md)

## 验证与发布准备

```sh
julia --project=. --check-bounds=yes -e 'using Pkg; Pkg.test()'
julia --project=. examples/basic.jl
julia --project=. examples/data_import.jl
julia --project=. benchmarks/runbenchmarks.jl
```

[实际验证与待办](DEVELOPMENT_REPORT.md) · [人工审查地图](docs/src/review.md) · [同类包调研](docs/src/ecosystem.md) · [名称与质量实测](docs/src/quality.md) · [注册要求](docs/src/registration.md)

本版代码、测试和文档包含 Codex 的实质性 AI 辅助贡献；已做自动验证与独立代理审查，人工维护者对全部代码的理解和手动审查尚未完成。正式注册前须完成该工作，见 [General 的 LLM 政策](https://github.com/JuliaRegistries/General#is-there-any-policy-regarding-the-use-of-llms-in-registered-packages)。

MIT license。没有嵌入真实行情、访问令牌或其他项目的复制实现。
