# blink-fff.nvim

A [blink.cmp](https://github.com/Saghen/blink.cmp) completion source that
suggests identifiers from the whole project. Search runs inside
[fff.nvim](https://github.com/dmtrKovalenko/fff.nvim): no external `rg`,
`git grep` or subprocess per keystroke.

## Requirements

- Neovim 0.10+ (tested on 0.12.6, LuaJIT)
- [blink.cmp](https://github.com/Saghen/blink.cmp) as the completion engine
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim) with its compiled
  library available

## Install

With lazy.nvim and blink.cmp:

```lua
{
  'Saghen/blink.cmp',
  dependencies = {
    'dmtrKovalenko/fff.nvim',
    'your-name/blink-fff.nvim',
  },
  opts = {
    sources = {
      default = { 'lsp', 'path', 'buffer', 'fff' },
      providers = {
        fff = {
          module = 'blink-fff',
          name = 'FFF',
          opts = {},
        },
      },
    },
  },
}
```

No setup call is required. Options are passed as the provider `opts` table.

## Options

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `prefix_min_len` | integer >= 1 | `3` | Minimum typed keyword length before searching |
| `get_prefix` | function | `nil` | Override the keyword; defaults to `context:get_keyword()` |
| `mode` | `plain` | `regex` | `fuzzy` | `plain` | fff search mode |
| `page_size` | integer >= 1 | `100` | Maximum matches returned by fff |
| `max_matches_per_file` | integer >= 0 | `20` | Per-file match cap |
| `time_budget_ms` | integer >= 0 | `80` | fff wall-clock budget; `0` means unlimited |
| `enforce_time_budget` | boolean | `true` | Apply the budget even with zero matches |
| `casing` | `smart` | `sensitive` | `insensitive` | `smart` | Search casing |
| `debounce_ms` | integer >= 0 | `30` | Keystroke debounce |
| `context_size` | integer >= 0 | `4` | Lines of context around a match in the documentation window |
| `fallback_to_regex_highlighting` | boolean | `true` | Use Vim syntax when no tree-sitter parser exists |
| `customize_icon_highlight` | boolean | `true` | Add the FFF icon metadata to items |
| `debug` | boolean | `false` | Log search diagnostics to `:messages` |
| `enabled` | boolean | `true` | Enable the source |

## Behaviour

- The typed keyword comes from blink's keyword range. A match range from fff
  is expanded to the surrounding identifier using byte offsets, then
  deduplicated by inserted text. The first location is kept for documentation.
- The source keeps up to 16 recent (buffer, prefix) results in an LRU cache.
  Backspacing reuses an earlier result; a new prefix searches again.
- Searches are synchronous because fff's Lua API has no cancellation. The
  source debounces, sets `time_budget_ms`, and discards stale results by
  generation. An in-flight search cannot be interrupted.
- The index is never rebuilt during completion. `cwd` and
  `wait_for_index_ms` are not passed to `content_search`.
- Empty results are valid while fff's initial scan is still running.
- The documentation window shows `path:line`, a divider, the surrounding
  lines, tree-sitter (or syntax) highlighting, and `BlinkFffMatch` extmarks
  on the matched token. Files larger than 64 KiB are read through a bounded
  byte window around the match instead of loading the whole file.

## Health

```vim
:checkhealth blink-fff
```

It reports whether blink.cmp and fff.nvim can load, fff's base path and
initialization state, and the active search budget.

## Development

```sh
mise run test     # busted specs under nlua
mise run lint     # selene
mise run format   # stylua
mise run check    # lint + test + format
```

Headless integration (requires fff on the runtimepath):

```sh
nvim --headless -u NONE -l scripts/smoke.lua
```

Benchmark the current directory:

```sh
nvim --headless -u NONE -l /path/to/blink-fff.nvim/scripts/bench.lua
```

## Known limitations

- No commands or toggles; use the `enabled` provider option.
- No git grep or ripgrep backend, and no external search fallback.
- Completion results do not show `path:line`; the documentation window does.
- No multi-root or additional-path support; configure fff itself.
