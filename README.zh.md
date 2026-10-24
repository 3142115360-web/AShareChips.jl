# AShareCostDistributions.jl 中文说明

`AShareCostDistributions.jl` 是用于研究 A 股筹码（估计持仓成本）分布的 Julia 包。它用日线成交区间和有效换手率递推成本直方图，输出平均成本、获利比例、成本分位数、集中度和历史快照。

它是统计估计模型，不能还原真实账户持仓，也不宣称与通达信等专有软件的内部算法一致。

## 安装

General 注册合并后，可通过 Julia 包管理器安装正式版本：

```julia
using Pkg
Pkg.add("AShareCostDistributions")
```

如需测试当前开发分支，可按仓库地址安装：

```julia
using Pkg
Pkg.add(url="https://github.com/3142115360-web/AShareCostDistributions.jl", rev="main")
using AShareCostDistributions
```

需要 Julia 1.10 或更高版本。运行时只使用标准库 `Dates`。

## 功能和假设

- `PriceGrid` 上的成本直方图，以及 Uniform、Triangular、Empirical 三种日成交模型。
- 线性和指数有效换手模型。
- 平均成本、获利盘比例、成本分位数和集中度。
- 显式价格基准、换手分母和除权事件；不接受含糊的数据口径。
- CSV 数据、参考直方图、除权事件和指标摘要的严格导入与比较工具。

核心递推是 `C_t(p) = (1 - α_t) C_(t-1)(p) + α_t D_t(p)`：`D_t` 是当日成交成本的估计分布，`α_t` 是可配置的有效换手。

完整的英文 API、数据契约、除权假设和验证方法见[文档站](https://3142115360-web.github.io/AShareCostDistributions.jl/)。仓库包含合成基准、跨网格比较工具和一个公开市场模型对照；该对照存在可测量偏差，未完成对任何专有行情终端的验收。

许可证为 [MIT](LICENSE)。提交修改前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
