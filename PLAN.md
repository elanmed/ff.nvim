# Plan: Additional Test Coverage

## Style & approach

Following the existing conventions in `tests/test_ff.lua`:

- **Structure & naming**
  - Organize by module: `T["H"]`, `T["F"]`, `T["P"]`, `T["find"]`; one sub-set
    per function with a `#`-prefix (mini.test convention for filtering).
  - Test names are behavior sentences ("avoids adding deleted files"), not
    function names.
  - Group cases sharing state under a sub-set (e.g. `["update_type=increase"]`).
- **Isolation via hooks, not mocks**
  - No mocking framework. Tests run in-process against real code; the only
    injection points are seams that already exist: `F._now` (clock), `H.cwd`,
    and `find_cmd` (stubbed externals like fd at this boundary, not deeper).
  - Each case starts from known test defaults; teardown restores captured
    process globals such as `vim.g.ff`, `vim.o.lines`, `H.cwd`, patched
    functions, and the clock. Picker caches and tracked test buffers are reset
    by local helpers in `tests/test_ff.lua`.
  - `post_once` handles one-time teardown (delete the unique sandbox).
- **Determinism**
  - Time stubbed to fixed timestamps; expected values precomputed once at file
    scope as named constants (`date_at_score_one_now`) — no inline math in
    assertions.
  - Floating-point comparisons derive expectations from the same formula;
    tolerate precision with near-equality where needed (item 15).
- **Real fixtures over stubs**
  - Real files on disk in a unique temporary sandbox, real JSON db, real
    `matchfuzzypos`, real buffers — stub only external processes.
- **Driving async & UI**
  - `@async` functions run via `vim.async.run(...):wait()`.
  - Integration cases observe behavior through `User` events (register
    autocmds, assert on `ev.data`), feed `<Plug>` mappings, and assert on
    window/buffer validity.
  - **A child process (`MiniTest.new_child_neovim`) is fine — and preferred —
    for UI-involving tests** (windows, previews, keymaps, screen state),
    matching mini.test's recommended pattern: `child.restart` in `pre_case`,
    `post_once = child.stop`.
- **Assertions**
  - `MiniTest.expect.equality` with exact expected values on observable
    outputs: db contents, formatted strings, event payloads, window/buffer
    state — not internal call counts.

## Test-file organization

- Keep `tests/test_ff.lua` as the single test file; add new sets alongside
  existing ones (`T["P"]["#refresh_frecency_cache"]`, `T["find"]` additions, a
  new `T["async"]` and `T["health"]` for `async.lua` / `health.lua`).
- If the file grows unwieldy, split per module (`tests/test_async.lua`,
  `tests/test_health.lua`) — mini.test collects all `tests/test_*.lua` files.
- Keep helpers local to `tests/test_ff.lua` until they are genuinely shared
  across multiple test files.

## Planned test cases

- `T["find"]["picker keymaps"]`
  - `opens a matching sandbox file selected from rendered search results`
  - `scrolls an active preview without moving the result selection`
