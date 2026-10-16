# API

```@meta
CurrentModule = AShareChips
```

```@autodocs
Modules = [AShareChips]
Private = false
```

仅导出符号及这里说明的行为属于公共契约。内部字段应视为只读；通过 `bin_edges`、`price_centers`、`probabilities` 获取副本。直接修改字段向量会破坏构造器保证，不受支持。
