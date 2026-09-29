# Pixel Doraemon V3 当前发布版 QA

这些文件直接来自 `../../output-v3/spritesheet.png`：

- `contact-sheet.png`：11 行完整动作联系图。
- `look-directions.png`：neutral 与 16 向注视检查图。
- `validation.json`：v2 图集结构校验结果。
- `source.json`：来源文件、Pet ID 与 SHA-256。

这里是分析当前动作的默认入口。不要使用 `run/**/qa/` 或 `qa/archive/` 中的同名文件代替它。

在引用这些图片前，运行 `../verify-current.ps1`；它会同时核对发布图集、当前 QA 和已安装 Pet。
