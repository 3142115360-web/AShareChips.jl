# 对照外部成本与获利指标

有些数据只提供每日平均成本、几个成本分位点或某个价格下的获利比例。它们可以直接与模型比较，但不足以确定完整筹码分布。`compare_metrics` 接收这些标量，不补造直方图，不返回 Wasserstein 距离、全分布最大 CDF 误差或软件兼容性结论。

```julia
using AShareChips

estimate = ChipDistribution(PriceGrid([8, 10, 12]), [1, 1])
comparison = compare_metrics(estimate; mean_cost=10.25,
    quantiles=[0.5], quantile_costs=[10.0],
    prices=[10.0], profit_ratios=[40.0], profit_unit=:percent)
@assert comparison.mean_cost_error == -0.25
@assert comparison.quantile_errors == [0.0]
@assert comparison.profit_errors ≈ [0.1]
```

所有误差都是模型估计减去参考值。成本与其误差使用价格单位；获利比例及其误差统一使用 0 到 1 的比例，`0.01` 的误差表示一个百分点。只比较明确传入的指标：缺少平均成本时，三个 `mean_cost_*` 返回值都是 `nothing`。分位点与成本、价格与获利比例须成对提供；每次调用至少提供一项指标。

## 文件流程

运行仓库中的合成示例：

```sh
julia --project=. examples/compare_metrics_csv.jl examples/metrics-analysis.toml
```

`examples/fixtures/metrics_synthetic.csv` 中的日期、代码、价格、指标均为手工合成数据，`provenance` 列也标记了这一点。第一天的均值、中位数与价格 10 下获利比例可由对称三角分布手算；第二个参考日故意给出近似参考值，用于展示误差，而非宣称与任何软件一致。

脚本使用与 `analyze_csv.jl` 相同的顶层行情设置、`grid` 网格、`model` 日内分布与换手设置，以及可选的 `events` 除权事件文件。它在完整输入行情上模拟一次；缺少参考的交易日仍参与历史筹码递推。参考设置如下：

```toml
[reference]
input = "reference.csv"
price_basis = "unadjusted"
profit_unit = "fraction"
matching = "intersection"
quantiles = [0.05, 0.15, 0.5, 0.85, 0.95]
quantile_columns = ["cost_q05", "cost_q15", "cost_q50", "cost_q85", "cost_q95"]

[reference.columns]
date = "date"
symbol = "symbol"
profit_price = "profit_price"
profit_ratio = "profit_fraction"
# Only add this mapping when the supplied field really is a mean.
# mean_cost = "weighted_mean"
```

`date` 和 `symbol` 默认映射同名列；其他指标须明确映射，不根据列名猜测。`quantiles` 必须是互不重复的 0 到 1 分位数，与 `quantile_columns` 一一对应，保留配置顺序。均值、分位成本和文件中的评价价格必须是非负有限数，分位成本须随分位数非递减。每行允许个别指标单元格为空，但至少提供一项指标；获利价格与比例必须同时有值或同时为空。核心 `compare_metrics` API 也允许负的有限评价价格；这个 A 股文件流程采用更窄的非负价格要求。

`profit_unit` 是必填的 `fraction` 或 `percent`，即使该文件只比较成本也需声明。比例输入的范围分别为 `[0,1]` 或 `[0,100]`；百分数只除以 100 一次。越界、非有限数、非零数转换为 `Float64` 后成为零，以及百分数转换时下溢都会拒绝。数据为 0.5 时它可能表示 50% 或 0.5%，仅凭值无法识别误声明；研究者须核查来源单位，脚本不猜测。

日期默认严格匹配 `yyyy-mm-dd`；参考文件可以用 `reference.dateformat = "yyyymmdd"` 等显式格式。日期须严格递增，不允许重复、截断日期或自动排序。证券代码保留前导零和后缀；参考文件每行须提供非空一致代码，或通过 `reference.symbol` / 顶层 `symbol` 明确声明。行情与参考的代码必须均已知且一致。脚本不会依据行情证券自动给无代码、无声明的参考文件贴标签。

行情与参考必须声明相同的 `price_basis`。这只是必要条件；同名 `fixed_adjusted` 标签不保证两份数据使用同一复权基准，未复权序列也需要一致的公司行为处理。事件文件沿用 [除权事件文件](adjustments.md) 的先调整后换手规则；固定复权行情拒绝再次应用非恒等映射。日终参考指标可能晚于收盘才可用，比较日期不等于回测中可用的时间。

`matching = "strict"` 要求两份日期完全一致；`intersection` 只输出共同日期。程序返回值与控制台分别报告行情有而参考无的日期 `estimate_only_dates`、参考有而行情无的日期 `reference_only_dates`。不补数据、不截去递推历史；没有共同日期会报错。未匹配的参考行也会完成证券、单位、日期、数值和分位成本顺序验证，不能借由日期过滤绕过错误。

参考输入是简单无引号 UTF-8 CSV：接受首行 BOM、CRLF、空白行及单元格两端空白，拒绝空或重复表头、不同列数、无效 UTF-8 和任意列中的双引号。额外列可保存数据来源哈希等记录，解析时忽略。复杂 CSV 应先由完整解析器转换；脚本不联网获取数据。

输出长表表头为：

```text
date,symbol,metric,quantile,price,estimate,reference,error
```

`metric` 是 `mean_cost`、`cost_quantile` 或 `profit_ratio`；不适用的 `quantile` / `price` 留空。所有输入、配置和结果先验证再发布报告；已有文件、目录或链接均不会覆盖。返回值还包含 `output` 和逐指标的 `rows`，便于程序进一步分析。

## 上游字段需要按定义映射

[Tushare `cyq_perf` 官方文档](https://tushare.pro/document/2?doc_id=293) 将 `cost_5pct`、`cost_15pct`、`cost_50pct`、`cost_85pct`、`cost_95pct` 列为相应分位成本，将 `weight_avg` 列为加权平均成本。这些字段分别映射到分位数 `0.05/0.15/0.5/0.85/0.95` 和可选 `mean_cost`。证券可映射 `ts_code`，日期可映射 `trade_date` 并声明 `yyyymmdd`。`winner_rate` 还必须配上实际评价价格，先核查其单位、价格基准和更新时间再导入；脚本不自动认定评价价格等于任何文件的收盘价。

[AKShare `stock_cyq_em` 实现](https://github.com/akfamily/akshare/blob/fe10d1decb705e5f43cc8ca3339ca39e580fb8f4/akshare/stock_feature/stock_cyq_em.py) 当前将 `avgCost` 计算为累计筹码 50% 对应的离散成本，然后输出名为“平均成本”的列。这里应将它映射为 `quantiles = [0.5]` 的参考成本，不能映射到本包的均值。其 `benefitPart` 是指定收盘价下的比例；导入时仍需同时提供该价格。源码版本、窗口、网格、舍入和边界处理应与实验记录一起保存，不能仅凭字段名认定同口径。

上述映射依据公开文档和公开实现，不构成通达信内部算法说明。真实实验应另外记录原始来源、获取时间、文件哈希、参数、覆盖期间、初始化、除权与偏差；数值接近不等于真实账户持仓或软件精确复现。

本轮真实日行情上的独立算法实验见[对照报告](market_validation.md)。
