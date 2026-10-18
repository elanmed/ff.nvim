# Plan: Additional Test Coverage

Current coverage in `tests/test_ff.lua`: most `H` helpers, `F.update_file_score`
(happy paths), `P.format_filename`, `P.get_icon_info` (partial),
`P.get_weighted_file` (boosts), and two `find` integration cases.

## High priority — core logic with zero coverage

1. **`P.render_find_files`** ✅ (done)
   - **Ranking inputs**
     - Empty query renders frecency paths before find paths
     - Dedups paths present in both frecency and find caches
     - Non-empty query matches rel paths via `matchfuzzypos`
   - **Limits**
     - Stops considering results at `max_results_considered`
     - Slices rendered results to `max_results_rendered`
   - **Caching & staleness**
     - Reuses `weighted_files_per_query` cache on repeated query (no re-rank)
     - Stale tick (`P.tick` changed) → renders empty results (cancel empties the weighted/decorated lists)
   - **Output**
     - Decorated files carry `rel_path`, `icon_char`, `formatted_filename`
     - `hl_enabled=false` → decorated files have empty `match_idxs`
     - `hl_enabled=true` → icon highlight + fuzzy char highlights at expected columns
2. **`P.scale_fuzzy_to_frecency`** ✅ (done)
   - **Shape of the sigmoid**
     - Score increases monotonically with `fuzzy_score`
     - Very low score → near 0; very high score → saturates exactly to max_score
     - `score_per_char == midpoint` → ~half of max_score
   - **Opts**
     - Normalizes per char: same per-char score for different query lengths
     - Custom `steepness`/`midpoint` opts are honored
3. **`M.defaulted_gopts`** ✅ (done)
   - **Defaults when `vim.g.ff` unset**
     - Weights (open/modified/alternate/current buf, basename boosts)
     - Sigmoid (steepness, midpoint), `matchfuzzypos_batch_size`
     - `hl_enabled`, `icons_enabled`, `max_results_considered`,
       `fuzzy_score_multiple`, `benchmark_step`, `benchmark_mean`
     - `find_cmd` defaults to `fd --absolute-path --type f`
     - `max_results_rendered` derived from window height
   - **User overrides**
     - Explicit `vim.g.ff` values win over defaults
     - Does not mutate `vim.g.ff` (deepcopy)
4. **`P.refresh_frecency_cache`** ✅ (done)
   - **Cache population**
     - Populates `frecency_abs_path_to_score` from dated-files.json for cwd
     - Populates `frecency_rel_paths`
   - **Filtering & ordering**
     - Skips unreadable (deleted) files
     - Sorts `frecency_abs_paths` by score descending
   - **Score display state**
     - Updates `MAX_FRECENCY_SCORE` and `MAX_SCORE_LEN` when a score exceeds 99
5. **`P.refresh_files_cache`** ✅ (done)
   - **Find command**
     - Runs `gopts.find_cmd`, splits stdout into lines
     - Skips empty lines
   - **Cache population**
     - Normalizes each abs path
     - Fills `find_abs_paths` + `find_rel_paths`
     - `P.is_find_cache_empty` true before, false after refresh
6. **`P.refresh_open_buffers_cache`** ✅ (done)
   - **Buffer filtering**
     - Only loaded + buflisted buffers with names under cwd are cached
   - **Cache population**
     - Captures per-buffer `modified` flag
     - Clears `weighted_files_per_query`
7. **`M.setup()`**
   - **Debounced frecency updates**
     - `BufWinEnter` on a normal window schedules `update_file_score` after
       the 1s debounce
     - Re-entering the same file does not re-schedule (debounce by
       `last_updated_abs_file`)
   - **Skip conditions**
     - Skips floating windows
     - Skips unnamed buffers
     - Skips paths outside cwd
   - **Cache refresh on new files**
     - Triggers `refresh_files_cache` only when the file has no frecency entry
   - **Highlight registration**
     - Defines `FFPickerFuzzyHighlightChar` / `FFPickerCursorLine` highlight links

## Medium priority

8. **`F.compute_score` / `F.compute_date_at_score_one`**
   - **`compute_score`**
     - Returns 1 when `now == date_at_score_one`
     - Returns 0.5 after one half-life
     - Returns > 1 for future dates
   - **`compute_date_at_score_one`**
     - Returns `now` for score 1
     - Roundtrip: `compute_date_at_score_one(compute_score(x)) == x`
9. **Picker keymap actions** (via `find`)
   - **`ResultSelect`**
     - Opens the selected file, closes the picker
     - No-op on empty line
     - No-op while preview active
   - **Navigation**
     - `ResultNext` / `ResultPrev`: move selection, wrap at ends
     - No-op while preview active
   - **`ResultDeleteFrecencyScore`**
     - Removes db entry, refreshes caches, re-renders
     - No refresh when file has no frecency entry
   - **Close & input**
     - `Close`: closes input + results windows, exits insert mode
     - `InputClear`: empties the input buffer
     - `WinClosed` on input window closes the results window
   - **Preview scrolling**
     - `PreviewScrollDown`/`Up`: no-op when preview inactive
10. **`F.update_file_score` edge cases**

- **Unknown inputs**
  - `remove` for an unknown file: no error, cwd entry created
  - Unknown `update_type` treated as remove (entry nil'd)
- **Consistency**
  - Adding a file that is unreadable mid-run keeps db consistent

11. **`health.check`**

- **Icon dependencies**
  - `icons_enabled=true`, no icon library → `vim.health.error`
  - `icons_enabled=true`, icon library loaded → no error
  - `icons_enabled=false` → `vim.health.ok`, icon lib not required
- **Find command dependencies**
  - `find_cmd` unset + `fd` missing → error
  - `find_cmd` unset + `fd` present → ok
  - `find_cmd` set → ok
- Stub `vim.health`, `vim.fn.executable`, and `package.loaded` — no real deps

12. **`async.lua`**

- **`batched_iterator`**
  - Processes all entries; `on_batch` fires per `batch_size`
  - Default `batch_size` (100)
  - `should_cancel` mid-batch flushes `on_batch` when `num_processed > 0`,
    then completes
- **`throttled_iterator`**
  - Processes all entries, then callback fires
  - `should_cancel` stops before completing iteration

## Low priority — mechanical/logging

13. **Window helpers**

- **`P.get_open_win_info`**
  - `results_height = floor(lines/2)`, `input_row = lines`, `results_row` computed
- **`P.save_minimal_opts` / `P.set_opts`**
  - save → mutate window opts → `set_opts` restores saved values

14. **`L` benchmarking internals**

- **Logging**
  - `L.log` / `log_content` / `log_line` append correctly formatted lines
    to `ff.log`
- **Timing**
  - `benchmark_step` "end" without "start" is a no-op
  - `record_mean=false` skips recording into `benchmarks_for_mean`
- **Lifecycle**
  - `P.reset_benchmarks` clears ongoing + mean tables
  - `P.print_mean_benchmarks` no-op when `benchmark_mean` false

15. **Reinstate TODO assertion** in "increments score on repeated calls"
    (precision issue)

- Assert with tolerance instead of exact equality

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
  - Every set's `pre_case`/`post_case` resets exactly the global state it
    touches: `P.caches.*`, `vim.g.ff = nil`, `P.caches.gopts =
ff.defaulted_gopts()`, `H.cwd`. Nothing leaks between cases.
  - `post_once` handles one-time teardown (delete the `test-ff` sandbox).
- **Determinism**
  - Time stubbed to fixed timestamps; expected values precomputed once at file
    scope as named constants (`date_at_score_one_now`) — no inline math in
    assertions.
  - Floating-point comparisons derive expectations from the same formula;
    tolerate precision with near-equality where needed (item 15).
- **Real fixtures over stubs**
  - Real files on disk in a `test-ff` sandbox, real JSON db, real
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
- Shared helpers (sandbox setup, cache reset, child bootstrap) go in
  `tests/helpers.lua` if duplicated across files.
