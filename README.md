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
    'UnderCooled/blink-fff.nvim',
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
| `file_trigger_char` | string (1 char) | `"@"` | Character that starts project file path completion |
| `mode` | `plain` \| `regex` \| `fuzzy` | `plain` | fff search mode |
| `page_size` | integer >= 1 | `100` | Maximum matches returned by fff |
| `max_matches_per_file` | integer >= 0 | `20` | Per-file match cap |
| `time_budget_ms` | integer >= 0 | `80` | fff wall-clock budget; `0` means unlimited |
| `enforce_time_budget` | boolean | `true` | Apply the budget even with zero matches |
| `casing` | `smart` \| `sensitive` \| `insensitive` | `smart` | Search casing |
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
- Typing the file trigger (`@` by default) switches the source to
  `fff.file_search`: project files are completed by fuzzy path. The inserted
  path is relative to `getcwd()`; the separator is the one typed after the
  trigger, else `completeslash`, then `shellslash`, then the platform default.
  `/` and `\` are trigger characters, so a typed path stays in the completion
  context.
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

Search-latency benchmark (see [Benchmark](#benchmark)):

```sh
nvim --headless -u NONE -l scripts/bench/fff.lua "$PWD" warm
nvim --headless -u NONE -l scripts/bench/ripgrep.lua "$PWD" warm
```

## Benchmark

Search latency against blink-ripgrep.nvim 2.2.7 (`reference/blink-ripgrep.nvim`),
measured 2026-11-17 in headless Neovim 0.12.6 (LuaJIT) on Windows 11 with the
"Ultimate Performance" power plan, `rg 15.1.0`, `hyperfine 2.0.0`.

Corpora: `reference/linux` (1.9 GB), `reference/rust` (279 MB) and
`reference/abkit` (7.0 GB), all git checkouts.

- `scripts/bench/fff.lua` waits for the fff index, then calls
  `blink-fff.searcher.default_search` — the production search path.
- `scripts/bench/ripgrep.lua` drives blink-ripgrep's ripgrep backend through
  its `get_completions` callback and times the first result.
- Both search `function`, `return` and `static`, 10 iterations per prefix.
  Warm numbers exclude the fff index build, which is reported separately.

### Cold first search (hyperfine)

`hyperfine --warmup 2 --runs 5` per plugin and repo: a fresh Neovim plus one
search. For blink-fff this includes the initial index scan, paid once per
session; blink-ripgrep rescans the tree on every search.

| Repo | blink-fff (index + search) | blink-ripgrep | Delta |
| --- | --- | --- | --- |
| linux (1.9 GB) | 1.756 s ± 0.012 s | 2.231 s ± 0.045 s | -21% |
| rust (279 MB) | 1.241 s ± 0.028 s | 1.271 s ± 0.025 s | -2% |
| abkit (7.0 GB) | 9.432 s ± 0.138 s | 9.636 s ± 0.359 s | -2% |

### Warm search, shipped defaults

One search per keystroke after the index is built. fff runs with
`page_size = 100` and `time_budget_ms = 80`; ripgrep returns every match.
`tokens` is the number of unique completions the source emitted.

| Repo | Prefix | fff p50 | fff p95 | fff tokens | rg p50 | rg p95 | rg tokens |
| --- | --- | --- | --- | --- | --- | --- | --- |
| linux | function | 8.5 ms | 10.1 ms | 13 | 1740 ms | 1929 ms | 464 |
| linux | return | 2.8 ms | 3.5 ms | 1 | 2040 ms | 2141 ms | 362 |
| linux | static | 2.6 ms | 3.3 ms | 0 | 1285 ms | 1370 ms | 499 |
| rust | function | 6.7 ms | 26.1 ms | 3 | 961 ms | 1040 ms | 339 |
| rust | return | 7.0 ms | 8.2 ms | 12 | 1127 ms | 1188 ms | 555 |
| rust | static | 5.0 ms | 5.6 ms | 8 | 911 ms | 979 ms | 604 |
| abkit | function | 7.1 ms | 14.0 ms | 7 | 8017 ms | 8328 ms | 2068 |
| abkit | return | 6.7 ms | 8.3 ms | 2 | 9031 ms | 10252 ms | 1215 |
| abkit | static | 19.2 ms | 22.3 ms | 3 | 7815 ms | 8025 ms | 1549 |

### Warm search, same result volume

fff with `page_size = 10000` and no time budget, so both plugins return
thousands of raw matches instead of a 100-record page. Not a shipping
configuration; it separates scan cost from the page cap. The ripgrep p50s are
the ones above.

| Repo | Prefix | fff p50 | fff p95 | fff tokens | fff raw records |
| --- | --- | --- | --- | --- | --- |
| linux | function | 167.9 ms | 211.6 ms | 563 | 10001 |
| linux | return | 39.8 ms | 90.3 ms | 56 | 10011 |
| linux | static | 44.1 ms | 60.6 ms | 46 | 10007 |
| rust | function | 73.9 ms | 297.3 ms | 179 | 10003 |
| rust | return | 58.2 ms | 87.1 ms | 437 | 10008 |
| rust | static | 63.1 ms | 73.9 ms | 436 | 10011 |
| abkit | function | 127.7 ms | 185.6 ms | 128 | 10000 |
| abkit | return | 147.8 ms | 170.2 ms | 31 | 10007 |
| abkit | static | 287.7 ms | 391.6 ms | 402 | 10000 |

### Result counts

The plugins count hits differently. fff returns one record per matched line
(`line_content` + `match_ranges`); blink-fff collapses those into unique
completion tokens. blink-ripgrep keeps one item per unique match text. The
default 100-record page is why fff offers few completions: 100 matching lines
dedupe to 1-13 identifiers. At 10000 records it offers 31-563 tokens depending
on how concentrated the prefix is; ripgrep offers 339-2068.

Spot check on `reference/rust`, query `function`, ripgrep run with
`--ignore-case` to match fff's smart casing: expanded token sets hold 1370
(fff) and 1371 (rg) identifiers. fff omits only the typed keyword itself, which
`tokens.candidates` filters out, and adds two identifiers from `.eslintrc.js`
files because fff indexes hidden files inside a git repo. `.git` is skipped
and `.gitignore` / `.ignore` / git excludes are honoured on both sides.

### Caveats

- Absolute numbers move with the OS page cache and power plan: the same matrix
  under an efficiency plan was ~2x slower for both plugins.
- Semantics differ: ripgrep searches `prefix[\w_-]+` with `--word-regexp`
  (prefix-anchored identifiers), while fff's default plain mode matches the
  keyword anywhere in the line and expands to the surrounding identifier.
- `time_budget_ms` can return partial results, so a capped search is fast by
  construction. The default-config table is the shipped UX, not equal work.
- Only the search step is measured; the documentation window, highlighting and
  blink.cmp item mapping are not.

## Known limitations

- No commands or toggles; use the `enabled` provider option.
- No git grep or ripgrep backend, and no external search fallback.
- Completion results do not show `path:line`; the documentation window does.
- No multi-root or additional-path support; configure fff itself.
- File completion inserts paths relative to `getcwd()`, walking up with `..`
  for files above it. Only a path on another drive keeps its absolute path.
