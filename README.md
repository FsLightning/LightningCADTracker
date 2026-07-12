# LightningCADTracker

`LightningCADTracker` 是 LightningCAD 的需求、缺陷、开发任务追踪与安装包发布中心，面向测试、需求、实施和开发协作使用。

## 仓库定位

- 需求、缺陷、开发任务和使用支持统一在本仓库提交 Issue。
- 安装包统一从本仓库的 [Releases](https://github.com/FsLightning/LightningCADTracker/releases) 下载。
- 本仓库不存放 `LightningCAD` 源代码；源码仓库是 [`FsLightning/LightningCAD`](https://github.com/FsLightning/LightningCAD)，仅面向开发人员。

## 与 LightningCAD 的关系

两个仓库共同服务于同一个 `LightningCAD` 产品，但职责不同，不存在源码依赖或 Git submodule 关系：

| 仓库 | 主要职责 | 主要使用者 |
| --- | --- | --- |
| [`FsLightning/LightningCAD`](https://github.com/FsLightning/LightningCAD) | 源码、构建、测试及原始 Release | 开发与发布维护人员 |
| [`FsLightning/LightningCADTracker`](https://github.com/FsLightning/LightningCADTracker)（本仓库） | Issue 协作及面向用户的安装包 Release | 测试、需求、实施、用户与开发人员 |

协作与发布链路如下：

```text
需求 / 缺陷 / 任务 -> LightningCADTracker Issues -> LightningCAD 开发与构建
LightningCAD Release -> 同步安装包 -> LightningCADTracker Releases
```

因此，代码变更和构建配置应提交到源码仓库；需求、缺陷、任务及使用支持应提交到本仓库。本仓库不参与 `LightningCAD` 的编译，收到的是源码仓库发布流程同步过来的安装包资产。

## 下载安装包

请进入 [Releases](https://github.com/FsLightning/LightningCADTracker/releases)，下载对应版本 Assets 中的 MSI：

```text
LightningCAD_Installer_vX.Y.Z.msi
```

Release 页面中 GitHub 自动显示的 `Source code (zip/tar.gz)` 是本 Tracker 仓库归档，不是 `LightningCAD` 源代码，也不是安装包。安装或测试时请下载 MSI。

## 提交反馈

请从 [New issue](https://github.com/FsLightning/LightningCADTracker/issues/new/choose) 选择合适模板：

- 需求评审：新功能、体验改进、业务流程建议
- Bug 报告：可复现缺陷、异常、安装或运行问题
- 开发任务：已经明确需要跟踪的开发工作
- 提问 / 支持：使用问题、验证疑问或需要协助的信息

提交 Bug 时建议附上版本号、CAD 平台、复现步骤、截图或录屏，以及必要的日志。

## 标签说明 (Labels)

### 性质 (Type)

| 标签 | 用途 |
|------|------|
| `Bug` | 故障与缺陷 |
| `Enhance` | 新功能需求与改进 |
| `Question` | 提问与确认 |
| `Draft` | 草稿/暂存 |

### 功能模块 (Module)

| 标签 | 用途 |
|------|------|
| `Panel` | 板材排版相关 |
| `JieDian` | 节点线相关 |
| `ShouBian` | 收边相关 |
| `Opening` | 门窗洞口 |
| `UI/UX` | 界面交互 |
| `Basic` | 基础功能/通用开发 |
| `WorkList` | 任务列表 |
| `CI/CD` | 构建与部署 |
| `Product` | 生产环境相关 |
| `CustomEntity` | 自定义实体 |

### 流程状态

| 标签 | 用途 |
|------|------|
| `Inbox` | 待处理的收件箱/需求池 |

### 其他

| 标签 | 用途 |
|------|------|
| `Document` | 文档改进 |
| `HelpWanted` | 寻求帮助 |
| `duplicate` | 重复 Issue |
| `invalid` | 信息不完整、无法复现或不适用 |
| `wontfix` | 明确不处理 |

## 发布同步说明

`LightningCAD` 源码仓库的 release workflow 会继续创建原始 GitHub Release。发布成功后，旁路 workflow 会把安装包同步到本仓库同 tag Release。

同步资产范围：

- 必需：`LightningCAD_Installer_${tag}.msi`
- 可选：`changelog.html`

本仓库 Release 长期保留，不跟随源码仓库的构建记录或清理策略发布源代码。
