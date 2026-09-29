# QA 目录说明

本目录把当前发布版证据与历史对比材料分开，避免把生成过程中的旧图误认为正在安装的 Pet。

## 权威顺序

1. `output-v3/pet.json` 和 `output-v3/spritesheet.png` 是当前发布包的唯一来源。
2. `qa/current/` 只保存从上述发布图集重新生成的静态 QA；判断当前动作时优先查看这里。
3. `qa/animations/` 保存当前发布版的逐行动画 GIF。
4. `qa/archive/` 仅供历史对比，不代表当前安装版本。
5. `run/` 是被 Git 忽略的生成与修复工作区。即使文件名含有 `final`，也不能据此判断它比 `output-v3/` 更新。

判断图集是否仍为同一版本时，先比较 `qa/current/source.json` 中记录的 SHA-256；哈希不一致时必须重新生成 `qa/current/`。

可以直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\qa\verify-current.ps1
```
