# 从文件到对照报告

仓库 `examples/analysis.toml` 可以配置一份日行情文件、价格网格和模型；新增可选的参考直方图文件与事件文件。所有内置例子均是合成数据，没有真实股票或商业终端验收结论。

```sh
julia --project=. examples/analyze_csv.jl examples/analysis.toml
```

会生成三日成本表，以及与两日手工参考直方图的误差表。缺少参考的第三日会明确列出；它仍参与历史递推。两份结果未必相等，示例刻意保留模型与手工参考的差异。重复运行须换输出文件名。

## 配置方式

文件路径相对于配置文件所在目录。价格网格必须覆盖全部成交范围和历史成本映射后的正质量支撑。

```toml
input = "fixtures/daily_synthetic.csv"
output = "analysis-result.csv"
turnover_unit = "percent"
price_basis = "unadjusted"
turnover_basis = "float_shares"
# events = "my_verified_events.csv"  # 可选，须针对这个输入数据核实

[grid]
lower = 8.0
upper = 14.0
step = 0.02

[model]
kind = "triangular"                 # 或 uniform
peak = "typical"                    # triangular 可用 close / vwap
turnover_model = "linear"           # 或 exponential
turnover_k = 1.0

[comparison]
input = "fixtures/reference_synthetic.csv"
output = "comparison-result.csv"
price_basis = "unadjusted"
mass_unit = "fraction"              # 或 percent / 显式 weights
matching = "intersection"           # strict 要求全部日期完全一致
```

事件文件不会依据跳空价格自动推断。`:fixed_adjusted` 输入禁止非恒等事件；首日事件需要已有 prior，示例脚本没有 prior 配置，因此不能用非恒等首日事件。库 API 支持显式 prior。随包事件样本是单独的合成文件，不应直接套用到未核实的行情。

## 程序接口

```julia
using AShareChips, Dates

series = read_bars("examples/fixtures/daily_synthetic.csv";
    price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent)
reference = read_distributions("examples/fixtures/reference_synthetic.csv";
    price_basis=:unadjusted, mass_unit=:fraction)
result = compare_history(series, reference;
    grid=PriceGrid(collect(8:0.02:14)), matching=:intersection)
@assert result.estimate_only_dates == [Date(2000, 1, 5)]
```

上例需要 `using AShareChips, Dates`。默认要求日行情与参考双方证券代码已知且一致；已知不同证券永远拒绝。没有代码的自有数据可由调用者显式设置 `require_symbol_match=false`，承担关联责任。双方价格基准标签必须相同，但标签不能验证实际因子、来源口径和数据许可。

`:strict` 要求相同日期；`:intersection` 返回公共日期的结果，并分别报告两侧未匹配日期。没有公共日期报错，不补造参考。每条结果含完整 CDF 最大差、Wasserstein 距离、成本均值/分位数误差和获利误差；误差方向是估计减参考。历史比较默认在当日收盘价比较获利比例，裸分布比较的默认价格仍是参考 bin 中点。

## 文件写出行为

在创建结果前完成输入、模拟、指标和参考比较的验证。已有文件、目录、硬链接或符号链接作为输出均拒绝。每个文件先写同目录临时文件，再通过不覆盖目标的硬链接发布；常规写入失败会清理临时文件。目标文件系统须支持硬链接。多个结果文件逐个发布，并非跨文件事务；已经完整发布的文件在后续输出失败时仍保留。

详细格式见[参考筹码文件](reference.md)、[除权事件文件](adjustments.md)和[导入行情文件](data.md)。真实对照仍需合法、口径一致的外部样本与来源记录。
