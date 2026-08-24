# Pixel Doraemon for Codex

一只像素风哆啦A梦 Codex v2 动画宠物，包含 9 组标准状态、16 向注视，以及可选的 Windows Companion 增强层。

Companion 提供本地鼠标注视、中文道具菜单、Codex 生命周期动作和自动更新的剩余额度漫画气泡。它是独立透明悬浮窗，不会覆盖原生宠物包。

<p align="center">
  <img src="qa/companion-quota-bubble-compact-preview.png" width="260" alt="Pixel Doraemon Companion quota bubble">
</p>

## 动画预览

| 待机 | 挥手 | 竹蜻蜓 |
| --- | --- | --- |
| ![待机](qa/animations/idle.gif) | ![挥手](qa/animations/waving.gif) | ![竹蜻蜓](qa/animations/jumping.gif) |

| 等待 | 任意门 / 思考 | 失败 |
| --- | --- | --- |
| ![等待](qa/animations/waiting.gif) | ![思考](qa/animations/running.gif) | ![失败](qa/animations/failed.gif) |

## 两种运行方式

| 模式 | 适合场景 | 特点 |
| --- | --- | --- |
| 原生宠物 `pixel-doraemon-v3` | 想直接使用 Codex 内置宠物系统 | 不启动额外进程，使用 Codex 固定的 v2 状态映射 |
| Companion 插件 | 想要额度气泡、中文菜单和更多桌面互动 | Windows 独立透明悬浮窗，通过 Codex hooks 获取状态 |

两者相互独立。若不想看到两个哆啦A梦，只启用其中一种即可。

## 动作与触发方式

| 动作 | 原生 Codex 宠物 | Companion |
| --- | --- | --- |
| 待机、眨眼 | 没有任务通知时自动播放 | 没有活动事件时播放 |
| 向左 / 向右跑 | 拖动宠物时播放 | 由图集保留，可随资源更新使用 |
| 挥手 | 首次唤醒或问候提示 | 单击宠物、部分任务完成事件 |
| 竹蜻蜓 | 鼠标移入原生宠物 | 双击宠物或右键菜单 |
| 等待 | Codex 需要输入、确认或授权 | `PermissionRequest` 事件 |
| 任意门 / 思考 | Codex 运行、思考或处理中 | 提交提示词或工具运行期间 |
| 检查成果 | 任务成功、结果等待查看 | 提交提示词及部分工具状态 |
| 失败 | 任务失败、阻塞或危险提示 | 工具失败事件或右键菜单 |
| 16 向注视 | Codex computer-use 光标事件 | 空闲时以头部为原点跟随本地鼠标，支持 DPI 换算、双死区防抖和最短方向连续转向 |

原生宠物的触发映射由 Codex 客户端决定，`pet.json` 和 spritesheet 只能提供对应画面，不能新增客户端事件。Companion 才负责额外的 hooks、菜单和额度气泡。

## 一键安装原生宠物（Windows）

```powershell
git clone https://github.com/Mootra/pixel-doraemon-pet.git
cd pixel-doraemon-pet
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会：

- 将 v3 安装到 `${CODEX_HOME}\pets\pixel-doraemon-v3`；
- 原子更新固定目录中的 `pet.json` 和 `spritesheet.png`；
- 将 `desktop.selected-avatar-id` 设为 `custom:pixel-doraemon-v3`；
- 保留旧版 `${CODEX_HOME}\pets\pixel-doraemon`，不会覆盖或生成重复档案。

安装后重启 Codex。

## 安装 Companion 插件（Windows，可选）

在仓库根目录执行：

```powershell
codex plugin marketplace add .
codex plugin add pixel-doraemon-companion@pixel-doraemon
```

然后新建一个 Codex 任务，让新版 hooks 生效。也可以双击 `Start-Doraemon-Companion.cmd` 手动启动；重复启动会复用现有实例。

Companion 默认每 60 秒从本机 Codex App Server 刷新一次额度，最低间隔为 15 秒；右键菜单可以立即刷新。它不读取或保存账号令牌。

## 更新

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\install.ps1
codex plugin add pixel-doraemon-companion@pixel-doraemon
```

安装脚本始终更新同一个 v3 宠物 ID 和目录，因此不会在宠物列表中累积时间戳副本。

## 卸载

卸载原生 v3 宠物：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

卸载 Companion 和仓库 marketplace：

```powershell
codex plugin remove pixel-doraemon-companion@pixel-doraemon
codex plugin marketplace remove pixel-doraemon
```

## 技术规格

- `spriteVersionNumber: 2`
- 单帧尺寸：`192 × 208`
- 图集尺寸：`1536 × 2288`
- 图集结构：`8 列 × 11 行`
- 第 0–8 行：Codex 标准动作
- 第 9–10 行：从 `000°` 开始、顺时针每 `22.5°` 一帧的 16 向注视
- Companion：Windows PowerShell 5.1、WPF、Codex lifecycle hooks

## 仓库结构

```text
output-v3/                         原生 v3 宠物包
plugins/pixel-doraemon-companion/ 可选 Companion 插件
qa/animations/                    精选动画预览
docs/specs/                       v2 图集和设计约束
install.ps1                       原生宠物安装
uninstall.ps1                     原生宠物卸载
```

## 说明

这是供个人学习与展示使用的非官方同人项目，与藤子·F·不二雄、哆啦A梦版权方及 OpenAI 无隶属或授权关系。角色相关权利属于各自权利人。详见 [NOTICE.md](NOTICE.md)。
