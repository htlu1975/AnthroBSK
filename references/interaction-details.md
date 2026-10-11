# Interaction details

- Hover markers such as `[hover first: Shoes | Bags]`, `[has-submenu]`, or
  `[expanded]` identify triggers. Hover the trigger, observe, then use the revealed
  item's ref. Listed labels are not refs; do not click the trigger unless its own
  action is wanted. If an expected control is missing and no marker identifies a
  trigger, try `observe --probe-hover` once. It touches the live page and costs
  seconds; use targeted hover once the trigger is known.
- `scroll-to` returns ancestor-clipped bounds in top-level viewport CSS pixels.
  Partial visibility suffices; hidden/fully clipped targets fail. It does not test
  occlusion. `wheel` sends signed deltas (at least one nonzero), not a guaranteed
  scroll distance. An optional target is scrolled into view first; without one,
  input lands at the viewport centre. Observe to check the page's response.

## Waiting for readiness

`wait-for-navigation` blocks until a page-lifecycle phase and is the reliable
way to wait for a load or a client-side route change:

```sh
bsk wait-for-navigation --wait-until load --session <id>
bsk wait-for-navigation --wait-until networkidle --timeout 20s --session <id>
```

Phases are `load` (default), `domcontentloaded`, `networkidle` and `commit`.
`--timeout` takes a duration such as `30s`, `1m` or `1500ms`. A timeout is
reported in the result rather than by a distinct exit status, so read the
output. Navigation invalidates refs: `observe` after it returns before acting.

`wait-ms` sleeps daemon-side for a fixed duration and takes no `--session`. It
is the blunt instrument for spacing actions out, never a readiness signal.

`wait-for-element` does not exist in CLI 0.3.2 - only `wait-ms` and
`wait-for-navigation` do. Do not write a selector wait. For a page change use
`wait-for-navigation`, then `observe` and act on fresh refs.

A wheel scroll is one discrete event. A human wheel arrives as several small
deltas that decay; one `wheel --delta-y 600` is a single jump. Where the scroll
itself matters, send two or three decreasing deltas instead, accepting that
each call costs about a second.

### Large observations

There is no default token cap. With `observe --max-tokens <n>`, follow a returned
`next_cursor`/`@more` when relevant content remains:

```sh
bsk observe --cursor <token> --session <id>
```

Each page replaces the ref map: use its refs before continuing and never reuse
refs from earlier pages. Continuation reads the same capture, without refreshing
or hovering; do not combine it with depth changes or hover probing. New observe/
snapshot or changed page identity invalidates continuation; then observe afresh.

## Diagnostics and other tools

Use `console` / `network` for bounded read-only diagnostics; follow returned
sequence cursors. `emulate --device iphone-14` affects one tab; `--off` restores it.
`evaluate` is a last resort: inspect JSON `.ok`, since a script exception can have
CLI exit code 0. Never evaluate secrets. `record start` captures user actions;
read its help first and never record banking, SSO or password-manager pages.
Use `bsk --help` to find navigation/history, tab, wait and window commands.
