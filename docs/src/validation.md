# 对照误差与网格敏感性

`compare_distributions` 比较两个已经定义好 bin 边界的筹码直方图。
`grid_convergence` 在同一组观测和模型假设下改变价格网格，报告相对于指定网格的误差。
它们不拟合参数，也不下载市场数据。下面的可运行示例全部使用合成数据；真实行情、供应商及通达信对照仍须实际执行。

## 分布比较

本包把每个 bin 的质量均匀铺在其边界之间，因此 CDF 连续且逐段线性。两个分布可以使用不同边界、不同支撑和不同 bin 数；比较过程保留各自的直方图语义，不先把某一方重分箱到另一方。

```julia
using AShareChips

reference = ChipDistribution(PriceGrid([1, 3]), [1])
estimate = ChipDistribution(PriceGrid([1.75, 3.75]), [1])
comparison = compare_distributions(estimate, reference;
                                   quantiles=[0, 0.1, 0.5, 0.9, 1],
                                   prices=[1.5, 2.0, 3.0])
@assert comparison.wasserstein1 ≈ 0.75
@assert comparison.max_cdf_error ≈ 0.375
@assert comparison.mean_cost_error ≈ 0.75
```

以下记估计与参考 CDF 为 `F_est`、`F_ref`，分位数函数为 `Q_est`、`Q_ref`。所有有符号误差的方向均为 **估计减参考**。

| 返回字段 | 定义与单位 |
|---|---|
| `max_cdf_error` | 全价格范围的 `max(abs(F_est(p)-F_ref(p)))`；概率比例，范围 `[0,1]`。例如 `0.02` 是 2 个百分点。 |
| `wasserstein1` | 一维 Wasserstein 距离 `∫ abs(F_est(p)-F_ref(p)) dp`；价格单位，非负。要求双方使用同一货币和价格基准。 |
| `mean_cost_error` | 数学上为估计均值减参考均值；内部通过 CDF 差积分稳定计算，避免两个大均值相减丢失差异，单位为价格。 |
| `quantiles`、`quantile_errors` | 调用者给定的 q 副本及逐项 `Q_est(q)-Q_ref(q)`；误差为价格单位。 |
| `prices`、`profit_errors` | 比较价格的副本及逐项 `F_est(p)-F_ref(p)`；误差为概率比例。默认比较价格是参考网格的全部 bin 中点，包括零质量 bin。 |
| `comparison_points` | 双方所有 bin 边界的排序去重并集；用于完整 CDF 与距离积分。 |

CDF 差在相邻并集边界之间为线性函数，绝对值的最大值必定在端点取得，因此 `max_cdf_error` 对已表示的直方图是完整最大值，不是稀疏价格采样的近似。Wasserstein 距离对每段积分；CDF 差在段内跨零时，分别计算零点两侧的三角面积。上述“完整”均以 Float64 舍入为限，不能消除输入直方图本身的离散化误差。

q 必须为有限的 `[0,1]` 数值，`q=0/1` 对应正质量支撑边界；分位数遇到平坦 CDF 时沿用 `cost_quantile` 的最左逆定义。价格必须有限，可以位于双方支撑之外。q 和价格保留输入顺序，允许重复或空列表；重复点得到对应的重复误差。返回向量独立于输入向量，修改结果不会改变原分布。两个非负距离指标对调参数不变，有符号指标改变符号；对照获利比例时应显式给双方同一 `prices`，因为默认价格取自第二个参数。

## 网格敏感性

```julia
using AShareChips

bars = [DailyBar(low=1, high=3, close=2, turnover=0.2)]
grids = [PriceGrid([1, 3]),
         PriceGrid(collect(1:0.5:3)),
         PriceGrid(collect(1:0.25:3))]
rows = grid_convergence(bars, grids; model=TriangularModel())
@assert [r.bin_count for r in rows] == [1, 4, 8]
@assert [r.max_cdf_error for r in rows] ≈ [1/8, 1/32, 0]
@assert [r.wasserstein1 for r in rows] ≈ [5/32, 1/32, 0]
```

返回行顺序与 `grids` 相同，每行含 `bin_count`、`max_bin_width` 和分布比较的全部字段。默认参考是最后一张网格，调用者应明确选好这个顺序。可用 `reference_grid=another_grid` 指定额外参考；它不必包含在 `grids` 中。边界与参考相同的一次模拟会作为参考复用，因而其自身距离及有符号误差均为精确零。默认各行采用同一参考网格的中点作为获利比例比较价格。

空网格列表报错。`BarSeries` 可以直接传入，保留其价格基准检查，固定复权序列仍拒绝非 identity adjustment。其他观测和 adjustment 迭代器只读取一次，再供每个网格使用。其他 `chip_distribution` 关键字照常传递，包含模型、换手模型和公司行为映射；每张网格都必须完整覆盖所有日价格范围及映射后正质量支撑，否则报错。粗 bin 可能把日内支撑向外扩展，随后发生除权映射时也必须覆盖这些扩展后的 bin，不能仅检查真实 low/high。

本函数只允许 `initial=nothing`。将一个 prior 自动重分箱到各网格会改变初始状态，使比较同时混入 prior 误差；需要 prior 的研究应由调用者显式准备每个网格上的初始分布，分别运行 `chip_distribution`，再使用 `compare_distributions` 对照。

最后一张网格的零误差只说明参考与自身相同。细网格是离散化参考，不是真实持仓；更细网格不保证任何模型、任意网格顺序或反复除权重分箱都具有单调误差。上面的下降是一个已知三角模型的解析测试结果。实际研究应报告网格边界、最大宽度、支持范围、参考选取和全部误差，并针对多个细网格继续检查稳定性。

## 真实行情与供应商对照数据约定

仓库不提供真实供应商筹码样本，也不宣称已经通过通达信一致性验收。以下是后续对照建议的 CSV 交换格式。日观测可以用 [`read_bars`](data.md) 导入简单、不带引号的分隔文本，得到 `BarSeries`；它支持列名映射和换手率比例/百分数转换。包含引号、多行字段或转义的通用 CSV 需要上游解析。参考直方图可通过 [`read_distributions`](reference.md) 导入；事件表可通过 [`read_adjustments`](adjustments.md) 对齐。授权、来源核验与清洗仍由上游执行。

日观测文件每只证券、每个交易日一行，推荐表头：

```csv
security,date,low,high,close,turnover,vwap,adjustment_scale,adjustment_shift,price_basis,turnover_basis,source,source_version
```

`date` 使用 ISO 日期并声明交易所日历；每只证券按升序去重。此交换格式的 `turnover` 为比例而非百分数，`turnover_basis` 记录流通股、自由流通股或总股本等分母定义。`security` 列可通过 `read_bars` 的 `columns` 映射为 symbol；基准声明由调用者以关键字提供，文本中的来源/基准元数据应另外保留。缺少 VWAP 记录为空，在构造时使用 `nothing`，不能由日 OHLC 自动推断。`adjustment_scale/shift` 是该日更新前的历史成本坐标映射；`read_bars` 不自动解析这两列，需要上游构造 `PriceAdjustment` 并显式传入。若所有价格已在固定复权基准中，这两个值应为 identity，避免重复调整。`price_basis` 必须同时适用于观测、prior、对照分布和比较价格。

参考直方图文件每个日期、每个连续 bin 一行，推荐表头：

```csv
security,date,bin_left,bin_right,mass,price_basis,source,source_version
```

边界须有限、非负、严格递增，相邻行满足前一 `bin_right` 等于下一 `bin_left`。有间隔时应补足零质量 bin。`mass` 是 bin 概率质量，不是密度、成交量或百分数；上游应先检查非负、正总量及归一化误差，再构造对象。构造器会归一化权重，因此必须在构造之前检查来源单位，避免自动归一化掩盖错误。若来源只提供单个价位及数量，需要在研究协议中明确边界/价格精度和分箱假设；不能把未声明宽度的价位直接认定为本包的连续直方图。

另行保存数据获取时间、来源页面/接口和版本、合法使用范围、缺失日处理、首日 seed 或 prior 的日期与来源、历史窗口、复权因子出处、模型参数及比较指标定义。缺失参考日期应记录并跳过，不能合成供应商值。通达信或其他软件若仅提供获利盘、成本分位数等摘要，应直接比较已明确的同名指标，不能由少量摘要伪造完整分布后声称完成 CDF 对照。

误差报告必须区分“本包的直方图数值误差”与“特定数据、特定配置下的供应商口径偏差”。即使数值高度一致，也不能据此证明真实账户持仓成本、恢复通达信的未公开内部算法，或说明任何交易策略有效。

微小正质量小于机器 epsilon 时，对照会触发内部精确有理数归一化与积分；结果仍转为 Float64。日行情、参考直方图和事件表的完整接入见[文件对照流程](workflow.md)。
