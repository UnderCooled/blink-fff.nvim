# PLAN

状态：**未实施**。本文完成于参考方案调研之后，先定契约与验证方式，再写代码。

## 1. 调研结论

### 1.1 blink.cmp source 契约

以 `reference/blink.cmp` 为准（用户当前主线版本，`3d3631f`）。接口定义在
`reference/blink.cmp/lua/blink/cmp/sources/lib/types.lua`，自定义 source 示例在
`reference/blink.cmp/doc/blink-cmp.txt`。

```lua
---@class blink.cmp.Source
---@field new fun(opts: table, config: blink.cmp.SourceProviderConfig): blink.cmp.Source
---@field enabled? fun(self: blink.cmp.Source): boolean
---@field get_completions? fun(self, context, callback: fun(response?: blink.cmp.CompletionResponse)): (fun(): nil) | nil
```

callback 结果：`{ items, is_incomplete_forward, is_incomplete_backward }`。
item 用 LSP `CompletionItem` 字段。

`blink.cmp.Context`（`completion/trigger/context.lua`）提供 `pos`、`line`、
`bounds { line, line_number, start_col, length }`、`get_keyword()`；`cursor` 已标为 deprecated。
文档窗口用 `documentation.draw(draw_opts)`，`draw_opts` 为
`{ item, window, config, default_implementation }`，`window` 提供 `get_buf()` /
`get_width()` / `get_border_size()`。

### 1.2 blink-ripgrep 的结构

- `init.lua`：source 入口，按 `prefix_min_len` 截断，交给 backend，返回取消函数。
- `backends/backend.lua`：backend 只有 `get_matches(prefix, context, resolve)`。
- `backends/ripgrep/`：拼 `rg` 命令、解析 JSONL、生成 items。
- `documentation.lua` + `highlighting.lua`：读取匹配行上下文，treesitter 高亮，extmark 标出匹配。
- `search_prefix.lua`：从光标前文本提取最后一个标识符；字符集为 ASCII 字母数字、`_`、`-` 和 UTF-8 续字节。
- 候选值来自 `rg` 的 `prefix[\w_-]+` 整词匹配；按匹配文本去重，每个词只保留第一个位置。

结论：可以沿用“source 很薄、backend 负责搜索、parser 负责结果、documentation 负责预览”的切分，
但 backend 内部不再有进程/JSON 解析，只剩一次 fff 调用和字节级 token 提取。

### 1.3 fff.nvim 可用的公开 API

来源：`reference/fff/lua/fff/main.lua`、`reference/fff/crates/fff-nvim/src/lib.rs`、
`reference/fff/crates/fff-nvim/src/lua_types.rs`。

```lua
local fff = require('fff')
local result = fff.content_search(query, {
  mode = 'plain',              -- 'plain' | 'regex' | 'fuzzy' | 'definition_only'
  page_size = 100,
  max_matches_per_file = 20,
  max_file_size = ...,
  casing = 'smart',            -- 'smart' | 'sensitive' | 'insensitive'
  smart_case = true,
  time_budget_ms = 80,
  enforce_time_budget = true,
  trim_whitespace = false,
  classify_definitions = false,
  file_offset = 0,
  -- cwd / wait_for_index_ms 不使用，避免每次补全触发重建索引
})
```

每个 item 的字段（Lua 表）：

| 字段 | 含义 |
| --- | --- |
| `relative_path` | 相对 fff `base_path` 的路径 |
| `name` | 文件名 |
| `line_number` | 1-based 行号 |
| `col` | 0-based 字节列 |
| `byte_offset` | 行首在文件中的字节偏移 |
| `line_content` | 匹配行文本（已截断到显示上限） |
| `match_ranges` | `{ {start, end}, ... }`，0-based 字节偏移，相对于 `line_content` |
| `is_definition` | 是否像定义 |
| `git_status` / frecency 字段 | 可选排序依据 |

顶层还有 `total_matched`、`total_files_searched`、`total_files`、
`next_file_offset`、`regex_fallback_error`。

关键实现事实：

- `content_search` 最终调用 `fff.fuzzy.live_grep(...)`，**同步执行**；Lua 侧没有暴露
  `abort_signal`，不能取消已经开始的搜索。
- 首次使用会 `ensure_initialized()` 并 `file_picker.setup()`；索引在后台扫描。
  只有显式传 `cwd` 且目录变化时才等待重建索引（`wait_for_index_ms`）。
- fff 的 `plugin/fff.lua` 已在 `UIEnter` 时预热索引；如果用户设置 `lazy_sync = true`，
  则依赖第一次 API 调用初始化。
- `require('fff.fuzzy').parse_grep_query` 可以剥离 fff 的查询约束语法；普通标识符前缀用不到。
- fff 自带 `health.lua`，可复用其原生库/lmdb 检查结果。

### 1.4 与 blink-ripgrep 的关键差异

| 主题 | blink-ripgrep | 本项目 | 决策 |
| --- | --- | --- | --- |
| 搜索 | `rg` 子进程，JSONL | fff 进程内 FFI，Lua 表 | 去掉 backend 选择、JSON 解析和取消进程逻辑 |
| 查询来源 | 自建 LPeg 前缀提取 | `ctx:get_keyword()` | 默认用 blink 的关键词范围；保留 `get_prefix(ctx)` 覆盖 |
| 匹配语义 | `prefix[\w_-]+` 整词 | fff `plain` 子串 + 本地 token 扩展 | 默认 `plain`；保留 `regex`/`fuzzy` 配置项 |
| 候选值 | `rg` 直接返回整词 | fff 返回行 + 字节区间 | 需要 `tokens.lua` 做边界扩展与去重 |
| 并发 | 子进程可 kill | 同步、不可取消 | debounce + `time_budget_ms` + 代际丢弃 |
| 根目录 | `vim.fs.root` / `.git` | fff 自己的 `base_path` | 不改变 fff 根目录；文档路径用 fff 的 `base_path` 解析 |
| 预览 | 重新读文件 + treesitter | 同左 | 直接复用参考实现思路 |
| 测试 | busted + Cypress | busted（nlua） | 不做任何浏览器/TUI 自动化 |

## 2. 目标与非目标

### 目标

1. 注册为 blink.cmp provider 后，输入单词前缀即可补全项目中出现过的完整标识符。
2. 候选来自 fff 索引，不启动外部进程，不依赖 `rg`。
3. 文档窗口显示匹配位置附近源码、语法高亮、匹配标记。
4. 默认配置可用；索引未就绪、fff 未安装、二进制缺失时安全降级并可通过 `:checkhealth` 定位。
5. 单元测试可在当前 Windows 环境用 `mise run test` 运行。

### 非目标

- 不做文件选择器 UI，不复制 fff 的 picker。
- 不实现 git grep / ripgrep backend。
- 不做多根目录、`additional_paths`、自定义 ignore（首版交给 fff 配置）。
- 不做 Cypress/Playwright/截图测试。
- 不保证与 blink-ripgrep 的每一项配置名兼容。

## 3. 架构

```text
blink.cmp
  └─ get_completions(ctx, callback)
       └─ init.lua            ctx:get_keyword()、长度检查、代际
            └─ searcher.lua    debounce、缓存、调用 fff.content_search
                 └─ fff.content_search(prefix, opts)   -- 同步
                      └─ items.lua     结果 + base_path → 候选列表
                           ├─ tokens.lua   字节边界扩展、跳过同词、去重
                           └─ documentation.lua / highlighting.lua（draw 时）
```

缓存/去抖规则：

- `prefix` 长度小于 `prefix_min_len`：立即 `callback(nil)`。
- 同一个 buffer + 同一 `prefix` 的连续请求：直接返回缓存结果，不重复搜索。
- 新请求到来时递增 generation；旧 generation 的回调即使完成也丢弃。
- 用 `vim.defer_fn` 合并 `debounce_ms` 内的击键；定时器只保留最后一个。
- fff 调用参数固定为 `cwd = nil`、`wait_for_index_ms = nil`，禁止触发重建索引。
- `time_budget_ms = 0` 时在 health 中警告（会卡 UI）。

## 4. 配置草案

```lua
---@class blink-fff.Options
---@field prefix_min_len? number        -- default 3
---@field get_prefix? fun(ctx): string   -- default ctx:get_keyword()
---@field mode? 'plain'|'regex'|'fuzzy' -- default 'plain'
---@field page_size? number             -- default 100；fff 单次最多收集的匹配数
---@field max_matches_per_file? number  -- default 20
---@field time_budget_ms? number        -- default 80；0 = 不限制（不推荐）
---@field enforce_time_budget? boolean  -- default true
---@field casing? 'smart'|'sensitive'|'insensitive' -- default 'smart'
---@field debounce_ms? number           -- default 30
---@field context_size? number          -- default 4
---@field fallback_to_regex_highlighting? boolean -- default true
---@field customize_icon_highlight? boolean -- default true
---@field debug? boolean                -- default false
```

blink 注册方式（与参考方案一致）：

```lua
sources = {
  default = { 'buffer', 'fff' },
  providers = {
    fff = { module = 'blink-fff', name = 'FFF', opts = {} },
  },
}
```

## 5. 分阶段实施

### Phase 0 — 环境与脚手架（已完成一部分）

- [x] 修正测试链路：`.busted` 使用 `nlua`，rockspec 声明 `rockspec_format = "3.0"` 与
      `test_dependencies = { "nlua" }`。
- [x] `mise.toml` 在 `[env]` 注入 `lua_modules/bin`、`LUA_PATH`、`LUA_CPATH`；
      `test` / `test-focus` 改为 `busted spec/`。
- [x] `mise run lint` 增加 `run_windows` 分支：原 POSIX `if ...; then` 在 cmd.exe 下不可用。
- [ ] 建立 `lua/blink-fff/` 空目录与 `spec/blink-fff/` 第一个 spec，确保 `mise run test` 稳定通过。
- 验收：`mise run test` 输出 `N success / 0 failures`；`mise run lint` 通过。

### Phase 1 — API spike（先证伪，再写插件）

写一个一次性脚本（`scripts/spike.lua`，完成后删除），在真实 Neovim 中验证：

- fff 已初始化，`content_search('function', { mode = 'plain' })` 的字段与 1.3 一致。
- `match_ranges` 的字节偏移和 `line_content` 对齐；含中文、emoji 的行不撕裂 UTF-8。
- 在 `plain` / `regex` / `fuzzy` 下分别测 3 组前缀，记录 `time_budget_ms = 80` 时的耗时。
- 验证 `regex` 模式能否使用 `prefix[\w_-]+`（决定是否值得作为默认）。
- 验证 `relative_path` 与 `require('fff.conf').get().base_path` 拼接后文件可读。
- 验证首次索引未完成时调用是否安全返回空结果。

验收：脚本输出一张表：mode / query / matches / elapsed_ms / first_item 字段快照；结论写入本文“风险”节。
若 `plain` 的 p95 超过 60 ms，Phase 6 的收窄优化提前为必做项。

### Phase 2 — 纯函数核心（TDD）

模块：`tokens.lua`、`items.lua`、`config.lua`。

- 查询默认来自 `ctx:get_keyword()`；不在本项目重写关键词范围逻辑。
- `tokens.expand(line, start_col, end_col)`：返回完整 token；边界规则与参考一致；
  token 等于 prefix（忽略大小写）时返回 nil。
- `tokens.candidates(items, prefix)`：逐条展开；按 token 精确去重；保留首个位置。
- `items.to_completion(candidate, ctx)`：生成 `label`、`filterText`、`insertText`、
  `source_id`、`kind`、文档闭包。
- 单测覆盖：空行、行首/行尾、多匹配、重复 token、CJK、emoji、大小写不同的同名 token、
  偏移越界（防御性返回 nil）。

验收：`mise run test` 全绿；纯函数模块在 `nvim -u NONE` 下 require 不报错。

### Phase 3 — source 与搜索接线

- `init.lua`：`.new(opts)` 合并默认配置；`.enabled()`；`.get_completions(ctx, cb)`。
- `searcher.lua`：`pcall(require, 'fff')`；defer 合并；调用 `content_search`；
  用 `generation` 丢弃过期结果；错误只记录 debug，不抛给 blink。
- `get_completions` 返回取消函数，blink 在新 context 到来时调用它；取消只清除待执行的
  debounce 定时器，已经开始同步搜索无法中断。
- 查询：默认 `ctx:get_keyword()`；允许 `get_prefix(ctx)` 覆盖。
- 结果为空/fff 缺失/索引未就绪：`callback(nil)` 或空 items，不报错。
- 首次预热：`setup` 时 `vim.schedule` 调用一次 `pcall(require('fff').content_search...)`？
  **不**：只调用 `require('fff.core').ensure_initialized()`，避免在 setup 阶段搜索。

验收：headless 脚本加载最小配置，构造 `ctx`，调用 source 两次（相同前缀、变化前缀），
断言：相同前缀不重复搜索；结果 item 字段齐全；fff 缺失时返回空且不抛错。

### Phase 4 — 文档窗口

- 首行 `path:line`，分隔线，随后 `context_size * 2 + 1` 行。
- 文件路径用搜索时保存的 `base_path` 拼接；读取失败显示单行错误而不是抛异常。
- treesitter 可用时按文件类型高亮；否则按配置退回 Neovim 自带 syntax。
- 用 extmark 标记当前 token 的所有出现（参考实现对 git grep 的做法）；高亮组
  `BlinkFffMatch` 链接 `Search`，`default = true`。

验收：headless 测试构造 draw_opts 假 window，调用 `draw`，断言 buffer 内容和 extmark 数量；
真实视觉效果由用户在自己环境确认。

### Phase 5 — 健康检查、调试、文档

- `health.lua`：blink.cmp 可否加载；fff.nvim 可否加载；`fff.fuzzy.health_check`（若存在）；
  fff 的 `base_path`；索引是否仍在扫描；`time_budget_ms = 0` 警告。
- `debug.lua`：记录 query、耗时、item 数、丢弃代际；`config.debug` 打开后写 `:messages`。
- `README.md`：安装（依赖 fff.nvim）、blink provider 配置、全部选项、已知限制。
- `doc/blink-fff.txt`：可选；如果生成，加入 rockspec 的 `copy_directories`。

验收：`:checkhealth blink-fff` 在“fff 已装 / 未装”两种环境下都不报 Lua 错误。

### Phase 6 — 性能与体验收尾

- 用 `scripts/bench.lua` 在 3 个真实仓库上记录键入序列的 p50/p95；目标 p95 ≤ 60 ms。
- 如果超出：开启“前缀收窄”优化——plain 子串模式下，新前缀扩展旧前缀时先过滤缓存候选，
  命中则不调用 fff；未命中再搜索。regex/fuzzy 模式不启用。
- 检查接受补全后光标位置、重复触发、快速退格、切换 buffer、fff 尚未扫描完等场景。
- 删除所有一次性脚本；只保留可重复的 smoke/bench 脚本（若保留）。

验收：记录实测数字；用户在实际 Neovim 中确认可用。

## 6. 测试矩阵

| 层级 | 工具 | 覆盖 |
| --- | --- | --- |
| 单元 | busted + nlua | 查询提取、token 边界、去重、item 映射、文档行选择 |
| Headless 集成 | `nvim --headless -l scripts/smoke.lua` | 真实 fff 调用、空结果、缺依赖降级、source 回调 |
| 性能 | `scripts/bench.lua` | 单次搜索耗时、击键序列 p95 |
| 手动 | 用户自己的 Neovim | 补全菜单、文档窗口、高亮、无卡顿 |

不写：Cypress、浏览器、TUI 截图、CI 中启动真实 UI。

## 7. 风险与缓解

| 风险 | 证据 | 缓解 |
| --- | --- | --- |
| 同步搜索阻塞主线程 | `content_search` 直接调用 `fuzzy.live_grep` | 默认 80 ms 预算 + 30 ms debounce；Phase 6 收窄 |
| 无法取消搜索 | Lua API 未暴露 `abort_signal` | generation 丢弃结果；不重复发起相同查询 |
| 首次索引未完成返回空 | fff 后台扫描 | 空结果合法；health 显示扫描状态；不在补全中等待 |
| fff 二进制/版本不匹配 | `require('fff.fuzzy')` 可能失败 | pcall + health + 明确提示 |
| UTF-8 字节偏移误用 | `match_ranges` 是字节 | 单测覆盖中文/emoji；只用 `string.sub` |
| plain 子串匹配到词中部 | 例如搜索 `foo` 命中 `myfoo` | 与 `rg` 子串语义一致；token 扩展后交给 blink 过滤 |
| fff 查询约束语法误伤前缀 | `content_search` 支持 `*.rs` 等 | 前缀只允许标识符字符；不在首版暴露约束语法 |
| 文档路径拼接错误 | `relative_path` 相对 `base_path` | Phase 1 验证；Windows 用 `vim.fs.joinpath` |
| blink 版本漂移 | 本机为 2.x | 记录已测版本；health 打印版本；接口变更单独适配 |
| 公开 API 会覆盖 fff picker 的最后一次搜索元数据 | `content_search` 内部写 `grep_renderer.last_result` | picker 每次搜索都会重写；若出现异常再改用 `fuzzy.live_grep` |

## 8. 开放问题（默认决策）

1. 候选是否显示 `path:line`？默认**不显示**，与参考方案一致；文档窗口展示位置。
2. 是否按 frecency 排序？默认**保持 fff 返回顺序**，由 blink 自己的评分排序；如需再取自
   `total_frecency_score` 做 `sortText`。
3. 是否支持 `regex`/`fuzzy`？配置项保留，默认 `plain`；Phase 1 验证后再定默认。
4. 是否提供开关命令？默认只读 `opts.enabled`；不引入 snacks.toggle 依赖。

## 9. 完成定义

- [ ] 用户按 README 配置后，在真实 Neovim 中能补全项目标识符。
- [ ] 文档窗口有上下文、语法高亮和匹配标记。
- [ ] `mise run test`、`mise run lint`、`mise run format` 通过。
- [ ] fff 缺失或未扫描完时不报错、不卡 UI。
- [ ] 性能数字已记录，未达标的项有明确后续或已调整默认值。
- [ ] 没有 Cypress、浏览器测试或一次性调试脚本残留。
