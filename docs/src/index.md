# AShareChips.jl

以可复现的估计模型研究 A 股筹码成本分布。当前是尚未注册的 `0.1.0` 开发版，只依赖 Dates 标准库；采用 Float64 数值契约。

```jldoctest
julia> using AShareChips

julia> grid = PriceGrid([8, 10, 12]);

julia> bars = [DailyBar(low=9, high=9, close=9, turnover=0),
              DailyBar(low=11, high=11, close=11, turnover=0.25)];

julia> chips = chip_distribution(bars; grid);

julia> probabilities(chips) == [0.75, 0.25]
true

julia> average_cost(chips)
9.5

julia> profit_ratio(chips, 10)
0.75
```

先阅读[数学模型](model.md)和[数据与除权](assumptions.md)，再接入真实行情。无初始分布时第一天是 seed；示例中的零换手首日仍然完成初始化。

在包根目录构建完整文档：

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
python3 -m http.server --bind 127.0.0.1 --directory docs/build 8000
```

然后在浏览器打开本机 `http://127.0.0.1:8000`。CI 构建文档并保存 HTML artifact；远程托管尚未配置。

日期序列、文件接入及逐日结果表见[导入行情文件](data.md)；不同网格与供应商结果的误差比较见[精度与对照](validation.md)。包名及代码质量的实际检查见[发布准备证据](quality.md)。
