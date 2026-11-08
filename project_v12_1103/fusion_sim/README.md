# 重新验证

在 PowerShell 执行 `./run_fusion.ps1` 运行六项融合/云台/显示回归。
执行 `./sim/run_tests.ps1` 运行 97 项主回归和 5 组专项；默认 ModelSim 路径 D:/modelsim/win64，可用 -ModelSimBin 指定。
仅检查所有文件路径可用：`./sim/run_tests.ps1 -StageOnly`。
专项白平衡基准使用当前机器 C:/Users/shiping/Desktop/FPGA/TD/sim_release 的供应商单元模型，换机器需同步修改工具路径。
日志和临时 ModelSim 库由脚本重新生成；已交付日志位于 ../fusion_docs。
冻结参考只用于核对，不加入生产综合。负对照脚本故意注入错误，只有确认比较器检出预期错误才算通过。
