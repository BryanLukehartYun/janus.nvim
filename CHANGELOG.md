# Changelog

## Unreleased

- `ColorScheme` now fires when janus switches themes. The switch used to run
  inside a non-nested autocmd, which suppresses the event, so file trees and
  statuslines could keep the previous theme's highlights (#4).
- The `BufEnter` sync is deferred one tick. A plugin buffer that sets
  `buftype` just after being entered was treated as a normal buffer and
  resolved against cwd, flipping the theme (#4).
- Lazy-loading with `opts` no longer breaks revert. The auto-init applied
  the workspace theme before the user's `setup()`, which then recorded that
  theme as the one to revert to. Auto-init is now deferred one tick.
- Directory buffers (`nvim some/dir`) resolve to that directory instead of
  its parent.
- Starting Neovim on a dashboard or file tree applies the current
  directory's `.janus` instead of nothing.
- `:JanusSet` and `:JanusReset` take effect when run from a special buffer.
- `:JanusSet` with a colorscheme that does not load writes nothing, and a
  failed load no longer leaves `background` changed.
- Saving a `.janus` from Neovim applies it immediately.
- `.janus` values may be quoted.

## v1.0.0

Core declarative theme switching via `.janus` dotfiles. Walks up to the
nearest `.janus`, stops at a project boundary (`.git`), follows the buffer
you are editing, ignores special buffers, reverts on leaving (unless
`sticky`). Commands: `:JanusSet`, `:JanusGet`, `:JanusReset`.

Fixes since the initial cut:

- Auto-init now works when a plugin manager lazy-loads janus on an event
  with no `opts` or `config`. Previously the `once` `VimEnter` autocmd had
  already missed its fire by then, so janus did nothing.
- The pre-janus theme is captured only once a colorscheme actually exists.
  If janus's first sync beat the colorscheme plugin, `g:colors_name` was
  `nil` and the redundancy check wedged on `{nil, nil}` forever.
