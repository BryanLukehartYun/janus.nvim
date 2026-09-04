# Changelog

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
