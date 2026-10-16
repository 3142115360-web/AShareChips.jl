# Julia 生态调研

查询日期：**2026-10-15，Asia/Shanghai**。

在本次检索范围内，没有找到已核实、专门提供 A 股持仓成本分布估计、换手衰减及成本分位数的 Julia 包。这支持继续开发独立数值计算包，但不能证明 Julia 生态中完全没有类似实现。搜索引擎覆盖、未注册仓库和包的命名都会影响检索结果。

## 检索范围与证据

本次使用 `Julia 筹码分布`、`Julia chip distribution`、`Julia cost distribution`、`Julia volume profile`、`VolumeProfile.jl`、`AShareChips` 等关键词，核查项目自己的仓库与文档，并直接读取 General 注册表。

General 核查固定在提交 [`860c52b241b9c60ded22c86b802be6591c3b6f54`](https://github.com/JuliaRegistries/General/commit/860c52b241b9c60ded22c86b802be6591c3b6f54)，提交时间为 **2026-10-15 15:00:28，Asia/Shanghai**。名称查询使用该提交的完整 [Registry.toml](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/Registry.toml)。它是注册名称审计，**不是对全部注册包源码的功能审计**。

## 相关的已注册包

| 包 | 本次快照的最高注册版本 | 核实到的功能与关系 |
|:---|:---|:---|
| [MarketTechnicals.jl](https://github.com/JuliaQuant/MarketTechnicals.jl) | [0.6.0](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/M/MarketTechnicals/Versions.toml) | 官方文档列出移动均线、动量、波动率，以及 ADL、OBV、VWAP 等成交量指标；所查看的目录未列出换手衰减的持仓成本分布。可作为常规指标配套工具。 |
| [Indicators.jl](https://github.com/JTAmos/Indicators.jl) | [0.8.2](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/I/Indicators/Versions.toml) | README 列出多类技术指标及滚动统计，支持 Julia 数组与 Temporal 时间序列；所查看的功能清单未列出 A 股筹码模型。可配套使用，尚未证明是直接替代。 |
| TechnicalAnalysis.jl | [0.1.0](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/T/TechnicalAnalysis/Versions.toml) | [注册元数据](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/T/TechnicalAnalysis/Package.toml)指向 `p-w-rs/TechnicalAnalysis.jl`。本次 GitHub 仓库和 API 访问返回 404，未能核查功能或运行情况；不能因仓库不可访问就称其未注册或断言其不含筹码模型。 |
| [OnlineTechnicalIndicators.jl](https://github.com/femtotrader/OnlineTechnicalIndicators.jl) | [0.1.2](https://github.com/JuliaRegistries/General/blob/860c52b241b9c60ded22c86b802be6591c3b6f54/O/OnlineTechnicalIndicators/Versions.toml) | 官方开发文档介绍逐观测更新的技术指标，包括 VWAP、OBV 等；所查看的清单未列出 A 股成本分布。其流式计算设计值得参考，开发版文档不能视为注册版 API 保证。 |

功能证据来自 [MarketTechnicals 官方目录](https://juliaquant.github.io/MarketTechnicals.jl/dev/)、[Indicators README](https://github.com/JTAmos/Indicators.jl#readme)、[OnlineTechnicalIndicators 官方开发文档](https://femtotrader.github.io/OnlineTechnicalIndicators.jl/dev/)。General 的 Indicators 仓库地址仍写为 `dysonance/Indicators.jl`，本次 GitHub 请求重定向至 `JTAmos/Indicators.jl`。

本次 GitHub API 读取的 `pushed_at` 日期分别为：MarketTechnicals **2021-11-05**、Indicators **2022-12-06**、OnlineTechnicalIndicators **2026-09-07**；三者 `archived` 均为 `false`。这些仅是仓库元数据，不等于最近发布日期、当前 Julia 兼容性或维护承诺。本次没有安装或运行这些比较包。原始元数据可从 [MarketTechnicals API](https://api.github.com/repos/JuliaQuant/MarketTechnicals.jl)、[Indicators API](https://api.github.com/repos/JTAmos/Indicators.jl)、[OnlineTechnicalIndicators API](https://api.github.com/repos/femtotrader/OnlineTechnicalIndicators.jl)复查。

## 概念边界

本项目把两个对象区分开来：

- **成交量价格分布（volume profile）**：按价格累计一段时间内的成交量，描述成交发生的位置。
- **估计持仓成本分布（chip/cost distribution）**：用当日成交成本模型和持仓退出假设递推当前的成本概率质量。

即使 volume profile、VWAP、OBV 等工具使用相同的行情字段，也不因此拥有持仓退出模型。这里的区别是 AShareChips 的模型定义，并不表示已对上述项目的全部源码作否定性证明。

## 包名核查与风险

固定快照中未发现 `AShareChips` 的精确或忽略大小写的同名注册包。对注册名称做大小写无关的 `chip`、`ashare`、`volumeprofile`、`costdistribution` 搜索，结果为 `CHiPPS_BLIS_jll`、`ChipFiring`、`ChipSort`、`Chipmunk_jll`、`ImageChipper`、`PCHIPInterpolation`；这些名称结果没有显示一个明显同名的 A 股筹码包。

`AShareChips` 可以作为当前工作名称，但名称尚未获得注册表审核认可。名称长度、ASCII 与大小写形式符合基本命名形式；仍需考虑 `Chips` 是否足以向非领域用户说明股票成本估计的含义。[General 命名指南](https://github.com/JuliaRegistries/General/blob/master/NAMING_GUIDELINES.md)要求名称清晰并避免与既有包混淆。[AutoMerge 名称规则](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/#New-packages)还包括编辑距离和视觉距离检查；后续发布准备已通过当前官方 `AutoMerge.meets_distance_check` 的完整默认名称距离检查，记录在[名称与质量实测](quality.md)。通过固定快照的检查仍不代表正式注册时一定获准。

注册前应重新检查最新注册表及待审核的新包，完成名称距离检查，并由维护者判断英文包名是否足够清晰。

## 开发结论

保留严谨、可扩展的成本分布估计作为核心：明确每日成交分布、有效换手率、初始化、价格网格和除权坐标假设；通达信等软件作为外部对照目标。此调研没有证明任何未公开的商业算法，也没有完成跨软件一致性验证。

当前的独立包方向有合理依据；注册可行性取决于实际功能、测试、文档、维护者审查和 General 的审核，而不是“未搜索到同类包”这一点。发布准备及未完成事项见[注册准备](registration.md)。
