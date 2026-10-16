# 导入筹码对照分布

`ReferenceSeries` 保存单只证券的日期、对照分布和价格基准。它用于接收已经整理好的参考直方图；参考来源可以是可公开的研究算法或有合法使用权限的数据导出。导入成功只代表格式与概率一致性检查通过，不代表已复现通达信等软件的算法。

仓库中的 `examples/fixtures/reference_synthetic.csv` **全部为手工合成数据**，不是通达信、券商或任何行情供应商的输出：

```text
date,bin_left,bin_right,mass,symbol
2000-01-03,8,10,0.75,000001.SYNTHETIC
2000-01-03,10,12,0.25,000001.SYNTHETIC
2000-01-04,8,10,0.5,000001.SYNTHETIC
2000-01-04,10,12,0.5,000001.SYNTHETIC
```

```julia
using AShareChips, Dates

reference = read_distributions("examples/fixtures/reference_synthetic.csv";
                               price_basis=:unadjusted)
@assert trade_dates(reference) == [Date(2000, 1, 3), Date(2000, 1, 4)]
@assert probabilities(reference.distributions[1]) == [0.75, 0.25]
@assert average_cost(reference.distributions[1]) == 9.5
```

每一行表示一个价格区间。`mass` 是区间的概率质量，而不是概率密度、筹码柱高度、累计获利比例或成交量。直方图区间内部采用与 `ChipDistribution` 相同的均匀分布解释。如果原始导出是每股成本点、累计概率或柱高，请先依据供应商公开定义在上游转换；本包不猜测这些定义。

## 质量单位必须明确

| 参数 | 数据含义 | 逐日检查 |
|---|---|---|
| `mass_unit=:fraction`，默认 | `0.75` 表示 75% 的筹码 | 每日质量合计必须在 `mass_tolerance` 内接近 1 |
| `mass_unit=:percent` | `75` 表示 75% 的筹码 | 每行除以 100 后，使用相同的合计检查 |
| `mass_unit=:weights` | 明确声明数据为非负相对权重 | 每日必须有正权重，然后归一化 |

`mass_tolerance` 默认是 `1e-6`，表示合计与 1 的**绝对误差**，必须是非负有限数。通过合计检查后，构造器会归一化已接受的舍入误差。默认口径下合计为 100 的百分数数据、合计为 0.01 的重复除百分数数据、缺失质量和溢出的概率合计都会拒绝；适配器不会自动修正它们的单位。`:weights` 是用户显式允许任意权重归一化的选项；有限但原始合计溢出的权重使用缩放后归一化。

所有边界与质量必须能表示为有限 `Float64`，边界非负，质量非负。允许质量为 0 的区间，但全日质量不能全部为 0。每个区间右边界须大于左边界、宽度有限；同日区间须按升序紧邻，前一区间的右边界必须与后一区间的左边界数值完全一致，不接受重叠、缺口或重复区间。区间边界的不一致需在上游明确处理，适配器不根据近似误差合并它们。

正质量若在文本数值转换、百分数除以 100 或权重归一化时变为无法表示的 0，会明确报错；不会将它当成用户输入的零质量区间。权重相对尺度过大时，应在上游重新选择可表示的数值模型或明确决定近似方式。

## 日期、证券与价格基准

同一天的所有区间必须相邻出现；日期组须严格递增，不能在之后再出现已经读过的日期。允许不同日期使用不同网格。日期必须完整匹配声明的 `DateFormat`；默认拒绝 `2000-01`、`2000-1-3` 等截断或不同格式。适配器不排序、填补交易日、推断停牌或校正信息可用时间。

`price_basis` 必须显式填写，与 `BarSeries` 相同：

- `:unadjusted` 表示每个快照在该日期的历史未复权价格坐标中。
- `:fixed_adjusted` 表示全部快照已经处于一个固定复权坐标系统中。

构造器和导入器只记录上述声明，不推断或执行除权调整。模型与对照数据进行逐日比较时，证券、价格基准、公司行为映射、初始状态、覆盖区间、日期及可用时间应由研究者核实。同样写了 `:fixed_adjusted` 也不能保证两份数据选择了同一个复权基准；含未来公司行为的基准可能引入前视问题。

`symbol` 列允许缺失；若存在，则每行必须有非空且一致的字符串，保留前导零和后缀。可另传 `symbol="000001.SYNTHETIC"`，文件中的证券代码须与它一致。单个文件不允许包含多只证券。

也可以直接构造参考序列：

```julia
reference = ReferenceSeries(
    [Date(2000, 1, 3), Date(2000, 1, 4)],
    [ChipDistribution(PriceGrid([8, 10, 12]), [3, 1]),
     ChipDistribution(PriceGrid([7, 9, 11, 13]), [0, 1, 1])];
    price_basis=:unadjusted, symbol="000001.SYNTHETIC")
```

这些 `ChipDistribution` 已经是正规化后的分布。日期与分布长度必须相同且非空，日期须严格递增。构造器复制日期、分布向量及每个快照的边界与质量数组；调用者之后修改原始输入不会改变对照快照。内部字段约定只读；通过 `trade_dates`、`bin_edges` 与 `probabilities` 获取副本。

## 简单无引号表格与自定义列

`read_distributions` 与 `read_bars` 使用相同的简单表格规则：首个非空白物理行作为表头，空白行忽略，接受首个物理行开头的 UTF-8 BOM 和 CRLF，表头及单元格两侧空白移除，错误带物理行号。重复或空表头、不同列数、无效 UTF-8、任意列中的双引号均拒绝。它不是通用 CSV 解析器；引号、转义、字段内分隔符或跨行字段应在上游使用 CSV.jl 等完整解析器。

```julia
io = IOBuffer("day;L;R;W;Code\n03/01/2000;8;10;75;000001.SYNTHETIC\n" *
              "03/01/2000;10;12;25;000001.SYNTHETIC\n")
reference = read_distributions(io; price_basis=:unadjusted, mass_unit=:percent,
    delimiter=';', dateformat=dateformat"dd/mm/yyyy",
    columns=(date=:day, left=:L, right=:R, mass=:W, symbol=:Code))
@assert isopen(io)
```

`columns` 是 NamedTuple：`date/left/right/mass` 必须映射，`symbol` 可省略或设为 `nothing`。映射名可为非空 String 或 Symbol，须互不重复，按大小写精确匹配表头。额外列忽略，但仍须满足无引号与整行宽度规则。分隔符须为单个字符，不能是双引号或换行。

传入路径时，适配器负责打开与关闭文件；传入 IO 时，无论成功或失败均不会关闭调用者的 IO。真实对照数据的授权、供应商算法说明和结果偏差应另行记录；本页合成示例仅验证解析与手工概率，不构成真实行情或通达信兼容性证据。
