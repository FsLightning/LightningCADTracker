# Cloudflare Workers + GitHub Releases 优先下载通道方案

> 状态：Worker 流式中转已实现并部署验证；官网双入口代码待 Landing 变更合并，当前不购买 Workers Paid
> 更新日期：2026-09-23

2026-09-23 线上验证已确认：Worker version `74cbad32-fedd-425c-8e8a-1cf04cf93f5d` 已部署；新域名健康检查为 `200`，v0.1.4 的 Cloudflare 与 OSS 独立完整下载均为 `72,828,109` bytes，SHA-256 与本页基线及 Tracker Release digest 一致，Range 返回 `206`，响应为 `no-store`。首次 PoC 曾验证 Cloudflare 缓存能力；最终方案因“不需要 CDN 加速”而关闭大文件缓存，改为把 Range 转发给 GitHub 并流式回传。

## 1. 结论

官网新增两个下载入口，但不替换或删除现有阿里云 OSS：

1. **优先下载**：Cloudflare Workers 反向代理 `FsLightning/LightningCADTracker` 的公开 GitHub Release 安装包。
2. **备用下载**：保留现有阿里云 OSS 直链，用户可以绕过 Cloudflare 直接下载。

优先通道不是 `302`：浏览器只连接 Cloudflare 域名，Worker 在服务端跟随 GitHub Release 跳转并把安装包字节流式传回。纯 `302` 会让浏览器最终直连 GitHub 资产域名，不能满足中国大陆用户规避 GitHub 直连不稳定的目标，因此已排除。

Cloudflare 通道在官网中始终排第一并作为默认下载按钮，不再根据访问地区降级为“条件优先”。青岛、武汉已经进行多次实际下载测试，最低速度均超过 `1 MB/s`；这项实测结果作为当前面向用户启用 Cloudflare 优先通道的依据。运营后仍需持续观察不同运营商和更多地区，但它不再是阻止方案上线的前置疑问。

**EdgeOne Blob 分片、后台下载并重新拼接 MSI 的方案已明确废弃**，不再作为备用实现或后续兼容方向。相较于分片方案，Cloudflare 反代公开 Release 的发布、校验、断点续传和故障回退边界更简单。当前不启用 Workers Caching；方案目标是稳定中转，不是 CDN 缓存加速。

## 2. 已确认事实

### 2.1 安装包来源

正确的用户发布源是公开仓库 [`FsLightning/LightningCADTracker`](https://github.com/FsLightning/LightningCADTracker)，不是私有源码仓库 `FsLightning/LightningCAD`。

Tracker README 已明确其职责：

- `LightningCAD`：源码、构建、测试及原始 Release，面向开发与发布维护人员。
- `LightningCADTracker`：Issue 协作及面向用户的安装包 Release。
- 当前发布链路为 `LightningCAD Release -> 同步安装包 -> LightningCADTracker Releases`。

截至 2026-09-23，Tracker 已改为 **Public**。公开 Release 资产可以匿名访问，因此 Cloudflare Worker 不需要保存 GitHub Token。实测 `v0.1.4` 的公开 MSI 地址先返回 GitHub `302`，随后得到安装包响应 `200`，并支持字节范围请求。

### 2.2 当前安装包基线

以 [`v0.1.4`](https://github.com/FsLightning/LightningCADTracker/releases/tag/v0.1.4) 为基线：

| 项目 | 值 |
| --- | --- |
| 文件名 | `LightningCAD_Installer_v0.1.4.msi` |
| 大小 | `72,828,109` bytes（约 69.5 MiB / 72.8 MB） |
| SHA-256 | `c37eebc0bd2e798df1a46324fef208f697221f4c97db7f0f626429f001ebbded` |
| Tracker 状态 | `uploaded` |
| 匿名访问 | 可用，`302 -> 200` |
| Range 基础能力 | GitHub 最终响应包含 `Accept-Ranges: bytes` |

该体积超过 EdgeOne Blob 免费版单值 25 MB 的限制。当前 Worker 不缓存 MSI，因此不以 Cloudflare 缓存对象上限作为方案依据。

### 2.3 Tracker 公开状态评估

**建议维持 Public。** 这与 Tracker 的面向用户定位一致，并带来以下直接收益：

- Worker 不保存 GitHub 凭据，不存在 Token 泄漏、轮换或权限失效风险。
- GitHub Release 可以作为可审计的公共发布源。
- 用户和维护人员可直接核对 Release、文件名、大小与摘要。
- Worker 只承担稳定域名、流式转发和通道控制，不承担私有仓库认证。

Public 同时意味着代码、提交历史、Issues、Pull Requests、Actions 历史和日志均可能被所有人查看，任何人也可以 Fork。GitHub 官方还说明，从 Private 改为 Public 时，现有 push rulesets 会被禁用；该项后续治理由仓库负责人处理。

仓库负责人已确认当前 40 条迁移 Issue 数据可以公开；本项目不再负责审查、清理或迁移这些数据，也不把它们列入 Worker 上线验收。仓库公开后的历史、Actions 日志、ruleset 和分支保护治理由仓库负责人处理，不阻塞下载通道实施。

### 2.4 实施责任与权限协作

后续 Cloudflare 下载通道的方案细化、Worker 实现、测试、文档、官网接入和发布链路调整主要由 Codex 负责。实现代码、测试和不含敏感值的配置可以存入 Git 仓库。

Tracker 已公开，因此 Worker 运行时不需要 GitHub Token。实施期间如遇外部账号或权限边界，由仓库负责人协助完成以下操作：

- 若 Cloudflare 明确要求当前用途必须付费，由负责人决定是开通 Paid 还是停用 Cloudflare 主入口；Codex 不自动购买或升级套餐。
- 首次创建 Worker 时提供对应 Cloudflare Workers `Admin` 权限，或由负责人先创建 Worker。
- 后续部署提供目标 Worker 的 `Editor` 权限。
- 创建或调整自定义域名时提供对应 Zone 的 `Workers Routes Write` 权限。
- 如果启用需要鉴权的 OSS 回源，再协助配置相应凭据。

实际 Token、密码或 OSS 凭据值不写入 Git；源码中只声明所需 Secret 名称，值通过 Cloudflare Worker Secrets 或 CI Secrets 注入。这样不会因凭据处理阻碍实现，也不需要在对话中传递凭据值。

## 3. 下载架构

```text
官网默认下载按钮
    -> lightningcad-download.278848.xyz/releases/{tag}/{file}.msi
        -> Cloudflare Worker（固定规则、Range 转发、流式响应、no-store）
            -> 首选源：LightningCADTracker Public Release
            -> 可选源站回退：同版本、同 SHA-256 的阿里云 OSS

官网备用下载按钮
    -> 阿里云 OSS 直链（绕过 Cloudflare）
```

这里有两层故障回退：

- GitHub 源站在响应开始前失败时，Worker 可以在校验固定版本路径、响应状态、类型和长度后回源同版本 OSS；同摘要由发布阶段保证。
- Cloudflare 本身不可用时，官网仍提供阿里云 OSS 直链，用户可以完全绕过 Cloudflare。

“Cloudflare 始终优先”指用户界面中的默认入口始终是 Cloudflare URL；它不妨碍 Worker 内部做受控源站回退，也不妨碍页面保留明确标注的备用按钮。

## 4. URL 与安全边界

推荐使用不可变版本路径，例如：

```text
https://lightningcad-download.278848.xyz/releases/v0.1.4/LightningCAD_Installer_v0.1.4.msi
```

当前不提供 `/latest`，官网和发布同步始终写入不可变版本路径，避免同一 URL 对应不同二进制文件。

Worker 不是任意 URL 代理，应遵守以下边界：

- 仅允许 `GET` 和 `HEAD`。
- 仓库固定为 `FsLightning/LightningCADTracker`。
- 只接受稳定版本 tag 和 `LightningCAD_Installer_vX.Y.Z.msi` 文件名。
- 发布同步严格校验 `tag=vX.Y.Z` 与 `fileName=LightningCAD_Installer_{tag}.msi`；Worker 再次校验同一不可变路径契约。
- 不接受用户传入 GitHub owner、repo、任意上游 URL 或任意文件路径。
- GitHub 返回的临时签名跳转只由 Worker 在服务端跟随，不把它固化为官网链接或发布配置。
- 对外响应必须流式转发，不能把 72.8 MB 文件整体读入 Worker 内存。

Tracker 已公开，因此默认方案中**不配置 GitHub Token**。如果将来重新改为 Private，才需要改用只授予 Tracker `Contents: Read` 的 GitHub App 或 fine-grained token，并重新评估凭据运维风险。

## 5. 流式中转、Range 与响应要求

版本化 MSI 返回：

- `Cache-Control: no-store`
- `Cloudflare-CDN-Cache-Control: no-store`
- 正确的 `Content-Length`
- `Content-Disposition: attachment; filename="...msi"`
- `Content-Type: application/octet-stream` 或受验证的 MSI 类型
- 上游存在时透传 `Content-Range`、`ETag` 与 `Last-Modified`

Worker 把客户端的 `Range` 与 `If-Range` 转发到 GitHub，由 GitHub 返回 `206 Partial Content`，Worker 保持状态码和 `Content-Range` 后流式返回。响应体直接使用 `response.body`，不能调用 `arrayBuffer()`、`blob()` 或其他整包缓冲 API。

GitHub 的最终下载地址包含短期签名参数。Worker 在服务端跟随该跳转，但不把临时地址返回浏览器或写入官网配置。当前明确不启用 Workers Caching；如果未来重新考虑缓存，必须作为独立决策重新核对套餐、条款、成本和 Range 行为，不能顺手开启。

Workers 响应体目前没有文档规定的大小上限。Worker 运行时内存限制为 128 MB，这也是必须流式转发、不能整包缓冲的原因。GitHub 在返回有效响应之前失败时可以自动尝试 OSS；一旦 MSI 响应已经开始，中途断线不能无缝切换到另一源，用户应点击 OSS 备用按钮重试。

## 6. 免费方案与合规建议

项目负责人当前决定避免付费，因此实施边界为：

- 保持 Workers Free，不自动开通 Workers Paid，也不添加以自动扣费为目的的配置。
- Free 当前为每天 `100,000` 次请求、每次 `10 ms` CPU；超过平台限额时主通道可能失败，OSS 备用按钮必须始终可用。
- 关闭 Workers Caching，不以 CDN 缓存或加速为目标；仍需监控请求量、源站错误和 Worker 限额。
- 安装包字节仍经过 Cloudflare，所以“没有缓存”不等于能够自行保证合规。Cloudflare 服务条款对大文件分发有专门边界；如果 Cloudflare 明确要求付费，先暂停或调整 Cloudflare 主入口，再由负责人决定，不绕过平台要求。

这不是“用了 Cloudflare 就一定稳定或永久免费”的承诺。Worker 必须保持严格白名单，不能成为开放代理，也不能滥用公共 GitHub 带宽。

Cloudflare 中国网络的境内节点产品仍要求 Enterprise 和独立订阅；本方案并不依赖境内节点。当前采用 Cloudflare 优先的依据是青岛、武汉的实际下载结果，而不是假定所有大陆网络都具备境内节点。后续应至少补测电信、联通、移动和非缓存流式场景。

## 7. 发布顺序

当前稳定发布流程中，Landing 更新与 Tracker 镜像是两条相邻但不同的流程：

- [`release-stable.yml`](https://github.com/FsLightning/LightningCAD/blob/main/.github/workflows/release-stable.yml) 在稳定发布过程中触发 Landing。
- [`sync-tracker-release.yml`](https://github.com/FsLightning/LightningCAD/blob/main/.github/workflows/sync-tracker-release.yml) 在稳定发布成功后，通过旁路流程把安装包同步到 Tracker。

如果官网先发布 Cloudflare 地址、Tracker 资产随后才出现，会形成短暂的优先链接 `404`。目标顺序应调整为：

1. 构建并生成 MSI、大小和 SHA-256。
2. 上传原始 Release 和阿里云 OSS。
3. 同步到 Tracker Release，并校验文件名、大小和 SHA-256。
4. 注册或验证 Cloudflare 版本路径，对 `HEAD`、Range 和完整下载做健康检查。
5. Landing 发布 Cloudflare 首选地址和阿里云 OSS 备用地址。

在发布顺序尚未调整前，也可以让固定的 Cloudflare 版本路径在 Tracker 资产未就绪时受控回源 OSS，但不能把一个尚未可用的 URL直接发布给用户。

此前的 [CAD PR #294](https://github.com/FsLightning/LightningCAD/pull/294) 和 [Landing PR #52](https://github.com/FsLightning/LightningLanding/pull/52) 记录了可重复的网站同步操作；它们是本次通道升级的发布背景。2026-09-23 已通过 Wrangler 部署 `lightningcad-download.278848.xyz`，并确认健康检查和 v0.1.4 元数据请求可用；官网双入口及后续同步调整已提交到 [Landing Draft PR #53](https://github.com/FsLightning/LightningLanding/pull/53)，该 PR 合并后才会正式导流。

## 8. 官网展示与失败行为

| 场景 | 默认按钮行为 | 备用入口 |
| --- | --- | --- |
| 正常 | Cloudflare 下载 Tracker Release | 阿里云 OSS 直链 |
| GitHub 源站失败、Cloudflare 正常 | Worker 受控回源同摘要 OSS | 阿里云 OSS 直链 |
| Cloudflare 失败 | 默认按钮可能失败，页面明确提示使用备用下载 | 阿里云 OSS 直链必须可直接点击 |
| Tracker 尚未同步 | 不发布该版本，或 Worker 临时受控回源 OSS | 阿里云 OSS 直链 |
| 文件摘要不一致 | 停止发布或返回明确错误，不能静默提供不同文件 | 保留上一可验证版本或人工处理 |

官网文案建议：

- 主按钮：`优先下载（Cloudflare）`
- 次按钮：`备用下载（阿里云）`

无需向普通用户解释 GitHub 302 或源站选择，只需清楚表达首选与备用关系。

## 9. 参考代码评审

收到的参考 Worker 可以作为最小 PoC 骨架，但不建议原样投入生产。

### 9.1 可以保留的思路

- `GH_OWNER` 和 `GH_REPO` 固定，避免成为可代理任意站点的开放代理；实际值应改为 `FsLightning` 和 `LightningCADTracker`。
- `redirect: 'follow'` 在 Worker 内跟随 GitHub Release 的临时签名地址，不把临时地址暴露为官网固定链接；客户端不会收到指向 GitHub 的 `302`。
- 直接返回 `response.body`，属于流式转发，不会主动把完整 MSI 读入内存。
- 透传 `Range`，为断点续传保留基础条件。
- 同时支持 `GET`、`HEAD` 的方向正确。
- Tracker 已公开，因此参考代码不携带 GitHub Token 正好符合当前方案。

### 9.2 生产前必须补齐的边界

| 参考代码现状 | 生产方案要求 |
| --- | --- |
| 未显式拒绝其他 HTTP 方法 | 只允许 `GET`、`HEAD`；其他方法返回 `405`。`OPTIONS` 仅在确实使用跨域 JS 请求时开放。 |
| `/download/` 和 `/latest/download` 后可拼接宽泛路径 | 使用版本化路由、固定仓库与严格文件名规则；不能把 Release 页面或任意资产都代理出去。 |
| 默认使用 `latest` | 当前不提供 `latest`，主下载只接受不可变版本路径。 |
| 只调用普通 `fetch()` | 当前显式使用 `cache: no-store`，对外同时返回浏览器与 Cloudflare `no-store`；未来若启用缓存必须另行设计。 |
| 直接把客户端 `Range` 传给 GitHub | 当前方案保留这一行为，并要求把上游 `206`、`Content-Range`、`Content-Length` 正确返回客户端。 |
| 任何 GitHub HTTP 响应都原样返回 | 只接受预期的 `200/206`、类型和长度；有效的越界 Range `416` 保持原语义，其余 `404`、`403` 与 `5xx` 进入 OSS 回源逻辑。 |
| 仅捕获网络异常 | 增加 GitHub 非成功状态、OSS 回退失败和结构化日志；响应开始后的中途断线交给用户使用页面备用入口重试。 |
| 向所有来源开放 CORS | 官网使用普通下载链接时不需要 CORS。只有浏览器脚本必须读取响应时才启用，并优先限定官网 Origin；不要默认 `Allow-Headers: *`。 |
| 把 `err.message` 直接返回用户 | 对外返回稳定、简短的错误码或提示；详细异常只记入受控日志。 |
| 没有版本元数据校验 | 大小和 SHA-256 在发布阶段完成校验；Worker 运行时校验路径、状态、类型和长度，不在每次下载时重新计算 72.8 MB 文件摘要。 |
| 没有 OSS 备用逻辑 | GitHub 源站失败时可在 Worker 内回源同版本、同摘要的 OSS；同时保留绕过 Cloudflare 的 OSS 页面按钮。 |

参考代码中的自定义浏览器 `User-Agent` 不是必要的安全措施，也不能替代资产白名单和状态校验。`ctx` 当前未使用；只有在增加后台日志等异步收尾任务时才需要 `ctx.waitUntil()`。

因此，参考代码的合适定位是：验证“公开 Tracker Release 能通过 Worker 流式下载并支持 Range”的快速样例，而不是最终生产实现。

## 10. 验收标准

上线前至少完成：

- Cloudflare 版本 URL 的 `HEAD` 返回成功，文件名和 `Content-Length` 正确。
- `Range: bytes=0-1023` 返回 `206` 和正确的 `Content-Range`。
- 完整下载 SHA-256 与 Tracker Release、阿里云 OSS 和发布记录完全一致。
- 普通 GET 与 Range GET 都能成功下载，并记录首字节时间和平均速度；响应不得命中 Workers 大文件缓存。
- 青岛、武汉复测不低于当前可接受基线；补测电信、联通、移动至少各一条线路。
- GitHub 源站失败演练可回源 OSS；Cloudflare 不可用时，OSS 备用按钮仍能直接下载。
- Worker 拒绝非允许仓库、非允许文件名、非稳定 tag、非 `GET/HEAD` 请求。
- Worker 运行时不依赖 GitHub Token；部署所需 Cloudflare 权限和可选 OSS Secret 已在目标环境中配置。

本阶段只涉及官网首次安装/手动下载安装包。现有桌面自动更新器暂时沿用其既有“单 URL 下载完整 MSI + 整包 SHA-256 校验”契约；这不是永久保持 OSS 的决定。

官网任务完成后，桌面自动更新作为后续任务单独设计。候选方向包括：Cloudflare 默认为第一通道并允许用户临时切换 OSS；Cloudflare 在响应开始或完整性校验前失败时自动回退 OSS；自动更新失败后提供打开官网下载页的明确入口。届时再决定用户配置、自动回退和网页下载之间的优先级，同时必须保留整包大小及 SHA-256 校验。

## 11. 参考链接

### 项目资料

- [LightningCADTracker README](https://github.com/FsLightning/LightningCADTracker#readme)
- [LightningCADTracker Releases](https://github.com/FsLightning/LightningCADTracker/releases)
- [LightningCADTracker v0.1.4](https://github.com/FsLightning/LightningCADTracker/releases/tag/v0.1.4)
- [CAD PR #294](https://github.com/FsLightning/LightningCAD/pull/294)
- [Landing PR #52](https://github.com/FsLightning/LightningLanding/pull/52)
- [Landing Draft PR #53：Cloudflare GitHub Release 中转通道](https://github.com/FsLightning/LightningLanding/pull/53)

### Cloudflare 官方资料

- [Workers 平台限制](https://developers.cloudflare.com/workers/platform/limits/)
- [Workers 定价](https://developers.cloudflare.com/workers/platform/pricing/)
- [Workers Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)
- [Workers Request](https://developers.cloudflare.com/workers/runtime-apis/request/)
- [Cloudflare Workers roles and permissions](https://developers.cloudflare.com/workers/authorization/workers/)
- [Cloudflare Workers Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare Application Services 条款](https://www.cloudflare.com/service-specific-terms-application-services/)
- [Cloudflare Developer Platform 条款](https://www.cloudflare.com/service-specific-terms-developer-platform/)
- [Cloudflare China Network](https://developers.cloudflare.com/china-network/)

### GitHub 官方资料

- [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [REST API endpoints for release assets](https://docs.github.com/en/rest/releases/assets)
- [Setting repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)
- [Quickstart for securing your repository](https://docs.github.com/en/code-security/getting-started/quickstart-for-securing-your-repository)
