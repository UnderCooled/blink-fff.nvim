# AGENTS.md

`blink-fff.nvim` is a blink.cmp completion source. It suggests identifiers from the whole project using fff.nvim's in-process index. fff owns indexing, matching and frecency; this repo is the blink adapter and the documentation window.

## Reference material (read-only)

- `reference/blink-ripgrep.nvim` — upstream v2.2.7 snapshot. Structural model: source → backend → result parser → items + documentation.
- `reference/fff` — fff.nvim snapshot. Source of truth for the `require('fff')` API and result shapes.
- `reference/blink.cmp` — the blink.cmp mainline the user runs (`3d3631f`). Source of truth for the source interface, context fields, item types and documentation draw options. Do not rely on the copy installed under `nvim-data`; it may lag.

Never edit anything under `reference/`. Never copy its Cypress, browser or TUI-snapshot test setup; this project does not use them.

## Environment (this machine)

| Item | Value |
| --- | --- |
| OS | Windows x64 |
| Neovim | `nvim` on PATH, v0.12.6, LuaJIT 2.1 |
| Real config | `%LOCALAPPDATA%/nvim-data/lazy`, with `fff.nvim` and `blink.cmp` installed |
| Isolated config | `.nvim/` (gitignored), launched with `nvim -u .nvim/init.lua` |
| Lua | project-local tree in `lua_modules/`; wrappers `lua.bat` / `luarocks.bat` (both gitignored) |
| Shell | bash tool is brush; use it for commands, `cmd.exe` only when a `.bat` wrapper requires it |

Never install LuaRocks packages globally. Use the project wrappers: `luarocks.bat install <rock>` targets `lua_modules`. If the wrappers do not exist yet, run `luarocks init --no-gitignore` once.

`mise.toml` injects `lua_modules/bin` into `PATH` and sets `LUA_PATH`/`LUA_CPATH` so `nlua` finds busted and its C modules. Run test tasks through mise; direct `busted` from a plain shell does not get that environment.

## Commands

| Command | Purpose |
| --- | --- |
| `mise run test` | busted specs in `spec/`, executed under Neovim Lua via `nlua` |
| `mise run test-focus` | only specs tagged `#focus` |
| `mise run lint` | selene on `lua/` and `spec/`, rejects committed `#focus` |
| `mise run format` | stylua on `lua/` and `spec/` |
| `mise run check` | lint + test + format |
| `mise run build` | first-time local dependency setup |

Notes:

- `mise run test` needs at least one spec file; busted exits 1 with “No test files found” on an empty `spec/`.
- `mise run lint` / `format` expect `lua/` and `spec/` to exist. `lint` has a separate `run_windows` branch because its POSIX `if ...; then` guard does not parse under cmd.exe; keep both branches equivalent when editing it.
- `mise run build` uses the global `luarocks` from PATH. On this machine prefer the project wrappers: `luarocks.bat init --no-gitignore` then `luarocks.bat install busted 2.2.0-1`. Do not duplicate installs into the user tree.

## Testing rules

- **No Cypress, no Playwright, no TUI screenshot tests.** Do not add them, do not “just borrow” the reference setup.
- Unit tests live in `spec/blink-fff/<module>_spec.lua`, use busted, and run under `nlua` (so `vim.*` is available).
- Test pure functions directly: query extraction, token expansion/dedupe, item mapping, documentation line selection. Extract these into modules that do not call `vim` at load time.
- For integration checks, write a headless script and run it with `nvim --headless -u <config> -l <script>`. Scripts must assert and exit non-zero on failure; no interactive input.
- The user verifies the real completion UI in their own Neovim. Never claim a visual or interactive check that you did not run; report only the commands and outputs you observed.
- Do not mock the fff FFI and call that integration. Mock only our own seam (a search function) for unit tests of the mapping layer.

## Runtime contract and invariants

- fff.nvim is a required runtime dependency. blink.cmp is a peer dependency. Do not shell out to `rg`, `git grep` or any external search tool.
- Load fff lazily: no `require('fff')` at plugin module load, only inside search/health paths guarded by `pcall`.
- One request path: `blink-fff/init.lua` → searcher → `require('fff').content_search(query, opts)`. Do not add a second backend without an explicit request.
- Never reindex per keystroke: do not pass `cwd` to `content_search`, do not call `change_indexing_directory`, and do not block on `wait_for_index_ms` during completion.
- `content_search` is synchronous. Keep a time budget, debounce keystrokes, and discard stale generations. Return a cancel function that clears the pending debounce timer; an in-flight synchronous search cannot be cancelled. Do not freeze Neovim to collect every match.
- fff returns byte offsets (`0-based` columns and `match_ranges`). Stay in bytes: slice with `string.sub` using `start + 1`. Never treat offsets as character indices.
- Use the reference blink context API: `ctx:get_keyword()` for the query, `ctx.pos` / `ctx.bounds` for ranges. `ctx.cursor` is deprecated; do not add new uses. Keep an optional `get_prefix(ctx)` override.
- fff may return partial results or none while the initial scan runs. Empty results are valid; never error the completion callback.
- Deduplicate candidates by inserted text. One item per unique token; keep the first location for documentation.
- Completion items must be safe for blink: set `label`, `filterText`, `insertText`, `source_id = "blink-fff"` and `kind`. Do not set a `textEdit` range unless it was computed from the blink context and verified.

## Code rules

- Lua 5.1 / LuaJIT, format with stylua, lint with selene. Match the reference plugin's module granularity; no premature abstraction.
- Annotate public module types and option fields with LuaLS comments. Comments only explain a non-obvious “why”; do not narrate code.
- Add configuration only when used by the implementation and documented in README.
- `vim.health` module required for any dependency or initialization failure that a user can hit.
- Keep the plugin usable with zero configuration beyond registering the blink provider.

## Layout

```text
lua/blink-fff/init.lua          blink source: new, enabled, get_completions
lua/blink-fff/config.lua        defaults + validation
lua/blink-fff/tokens.lua        expand byte ranges to identifier tokens, dedupe
lua/blink-fff/items.lua         fff result -> blink CompletionItem
lua/blink-fff/searcher.lua      fff content_search call, debounce, generation guard
lua/blink-fff/documentation.lua documentation window rendering
lua/blink-fff/highlighting.lua  match extmarks in the docs buffer
lua/blink-fff/health.lua        :checkhealth support
lua/blink-fff/debug.lua         opt-in diagnostics
spec/blink-fff/                 busted specs
doc/blink-fff.txt               vimdoc (generated or written at the end)
```

## Current status

Implemented: source, fff searcher, token expansion, item mapping, documentation
window, health check, debug logging, specs, headless smoke and bench scripts.
See `PLAN.md` for the phase results and measured numbers.
