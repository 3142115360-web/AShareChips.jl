# 日期序列与数据导入

`BarSeries` 将单只证券的观测日期、日线和研究口径保存在一起。价格基准与换手率分母必须显式填写；这些标签记录调用者的声明，本包无法验证供应商是否真的采用了该口径。

```julia
using AShareChips, Dates

bars = [DailyBar(low=9, high=11, close=10, turnover=0.05),
        DailyBar(low=9.5, high=12, close=11, turnover=0.12)]
series = BarSeries([Date(2000, 1, 3), Date(2000, 1, 5)], bars;
                  price_basis=:unadjusted, turnover_basis=:float_shares,
                  symbol="000001.SYNTHETIC")
grid = PriceGrid(collect(8.0:0.02:14.0))
history = dated_history(series; grid)
chips = chip_distribution(series; grid)
@assert history[2].date == Date(2000, 1, 5)
@assert probabilities(chips) ≈ probabilities(history[end].distribution)
```

上述日期、价格和证券代码都是合成示例，不代表真实行情。

## 明确价格与换手口径

| 参数 | 可用值 | 声明的含义 |
|---|---|---|
| `price_basis` | `:unadjusted` | 每个观测日当时的未复权价格；事件日可显式映射此前成本 |
| `price_basis` | `:fixed_adjusted` | 全部历史价格已经处于同一个固定复权坐标基准 |
| `turnover_basis` | `:float_shares` | 流通股作为换手分母 |
| `turnover_basis` | `:free_float_shares` | 自由流通股作为换手分母 |
| `turnover_basis` | `:total_shares` | 总股本作为换手分母 |

`DailyBar.turnover` 始终存储比例：`0.05` 表示 5%，允许大于 1。切换分母只更改元数据，不会重新计算换手率。请在上游根据证券、日期和供应商定义准备一致数据。

`:fixed_adjusted` 序列禁止任何非 identity `PriceAdjustment`，避免重复复权。默认 `adjustments=nothing` 或逐日 identity 调整均可。`initial` 必须已经与该序列的价格坐标一致；本包无法从概率分布自动判断该条件。固定复权基准若依赖未来公司行为，回测需另行评估前视问题。

日期必须非空、与 bars 等长并严格递增，重复日期与乱序均拒绝。本包不自动排序、去重或填补交易日，也不推断停牌、交易日历和信息可用时间。`trade_dates` 返回副本。构造时复制输入的 dates/bars；内部字段视为只读。

`chip_distribution(series)` 仍返回末期 `ChipDistribution`；`chip_history(series)` 仍返回状态向量；`dated_history(series)` 返回 `(date=..., distribution=...)` 向量，每条对应当日观测更新后的状态。所有模型、初始分布和网格参数沿用原有 API。

## 简单无引号分隔文件

`read_bars` 是针对简单表格的最小适配器，使用标准库 `Dates`，不依赖外部数据服务或解析包。它不是通用 CSV 解析器：任何双引号都被拒绝，包括额外列中的引号。需要 CSV 引号、字段内分隔符、转义、跨行字段或复杂缺失类型时，请先在上游使用 CSV.jl 等完整解析器，再用 `DailyBar` 与 `BarSeries` 构造模型输入。

仓库的 `examples/fixtures/daily_synthetic.csv` 是以下格式；所有行都是合成数据。

```text
date,low,high,close,turnover,vwap,symbol
2000-01-03,9,11,10,5,10,000001.SYNTHETIC
2000-01-04,9.5,12,11,12,,000001.SYNTHETIC
2000-01-05,10,12.5,12,8,11.5,000001.SYNTHETIC
```

```julia
series = read_bars("examples/fixtures/daily_synthetic.csv";
                   price_basis=:unadjusted, turnover_basis=:float_shares,
                   turnover_unit=:percent)
@assert series.bars[1].turnover == 0.05
@assert series.bars[2].vwap === nothing
```

`turnover_unit=:fraction` 是默认值，输入 `0.05` 为 5%；指定 `:percent` 后，输入 `5` 为 5%，适配器除以 100。适配器不猜测单位、不计算 VWAP、不从成交量与股本推算换手率，也不获取除权因子。

- 首个非空白物理行作为表头；前、中、后空白行忽略。异常信息中的行号仍按原文件物理行计算。
- 接受 UTF-8 BOM（只在第一物理行开头）与 CRLF；表头和值两侧空白移除。
- 表头名按大小写精确匹配，重复或空表头拒绝。每条非空数据行的列数必须与表头相同。
- `date/low/high/close/turnover` 必填且不可为空。数值必须可转换为有限 `Float64`，再接受 `DailyBar` 的范围检查；日期必须完整且精确匹配指定的 `DateFormat`，例如默认 `yyyy-mm-dd` 拒绝 `2000-01` 与 `2000-1-3`。
- `vwap` 与 `symbol` 列允许不存在。存在的空 VWAP 表示 `nothing`；存在的 symbol 列每行必须有非空且一致的证券代码。symbol 保留前导零与后缀，如 `000001`、`600000.SH`，不推断交易所。
- 可另传 `symbol="..."`；文件里的证券代码须与它一致。拒绝同一文件混入多只证券。
- 额外列忽略，但仍必须符合无引号格式与整行列数要求。文件至少包含一条观测。
- 传入路径时，适配器管理打开与关闭；传入 IO 时会消费其内容，但成功和失败均不关闭调用者的 IO。

## 自定义表头、日期与分隔符

```julia
io = IOBuffer("day;L;H;C;T;Code\n03/01/2000;9;11;10;5;000001.SYNTHETIC\n")
series = read_bars(io; price_basis=:unadjusted, turnover_basis=:float_shares,
    turnover_unit=:percent, delimiter=';', dateformat=dateformat"dd/mm/yyyy",
    columns=(date=:day, low=:L, high=:H, close=:C, turnover=:T, symbol=:Code))
@assert isopen(io)
```

`columns` 使用 NamedTuple，将模型字段映射到原始表头名；必填字段必须映射，`vwap/symbol` 可省略或映射为 `nothing`。指定映射需互不重复，映射名可为字符串或 Symbol。`delimiter` 是单个字符，不能为双引号或换行。

数据清洗、许可和调整因子的研究责任见 [数据与除权假设](assumptions.md)。真实行情与通达信等软件的对照仍需合法、口径明确且可审计的输入。
