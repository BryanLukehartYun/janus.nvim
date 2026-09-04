# janus.nvim

This plugin is a lightweight, minimal friction, and declarative colorscheme manager on repo by repo (folder by folder) for Neovim.

Drop a `.janus` file in a repo and it uses `cyberdream-light`. A subfolder inside it can say `rose-pine-dawn`; another repo entirely can be `elflord`. Every repo without a `.janus` just uses your preset colorscheme. This whole plugin as it is reads two keys and calls the colorschemes you already have installed, as needed.

The inspiration came from VS Code's Peacock extension. **janus.nvim** helps differentiate workspaces the way Peacock does, using the same idea of a per-workspace marker file. In this case, a `.janus` dotfile sets the colorscheme to reuse whole colorschemes as the per-workspace signal instead of tinting the window chrome an accent color.

> There was an attempt by me to use exrc and I did not like the game design behind it, because from my understanding of the documentation; there were more usecases for this and it was my attempt at making it simple as possible.

> Furthermore, when I did some research: I didn't find a whole lot of good options that mimicked Peacock besides the eponymous nvim plugin, which wasn't my intent as colorschemes could serve as "quasi" differentiation if you have multiple instances open for different repo, and the setup was relatively simple to do so, hence creating it.
> Furthermore my attempts to play with Peacock.nvim seemed to have some issues with the speed (seems to be noted), around this time I had noticed that i frequently changed themes per session and realized that this would serve as a good proxy essentially.

---

## Features

- The `.janus` file is plain text, no code execution.
- Written in Lua against core Neovim APIs (0.9+). Nothing else to install.
- Walks up to find the nearest `.janus`, stopping at a project boundary (`.git`) so a nested repo keeps its own theme.
- Follows the file you are editing and re-syncs on `DirChanged`. Pickers, file trees, terminals and the quickfix window are ignored, so they never change your theme.
- If the colorscheme you asked for is missing, janus keeps the current one and warns.

---

## Installation

Install with your preferred plugin manager:

### `lazy.nvim`

```lua
{
  "BryanLukehartYun/janus.nvim",
  event = "VeryLazy",
  -- opts = { ... }, -- see Configuration below; every key has a default
}
```

`setup()` is optional as the plugin auto-initializes with defaults at `VimEnter`. Pass `opts` (or call `require("janus").setup{}`) only to override them. The full list of keys and their defaults is in [Configuration](#configuration).

> Personally I just do `:JanusSet catppuccin` and that gets the job done.

---

## With Usage, comes great responsibility ;)

### 1. Set a theme for the current workspace

Inside any project or git repository:

```vim
:JanusSet cyberdream light
```

_(Tab-completion is supported for all installed colorschemes and background modes.)_

### 2. Manual `.janus` file

Alternatively, create a `.janus` file in the root of your project:

```ini
# .janus
colorscheme = cyberdream
background = light
```

Use the two keys `colorscheme` and `background` rather than a combined `colorscheme = cyberdream-light` token. janus reasons about the colorscheme name and `background` separately, and a scheme whose light and dark forms report the _same_ `g:colors_name` (cyberdream is the classic case; some rose-pine setups too) can't be told apart otherwise. See `:help janus-variants`.

Add `.janus` to your global `~/.config/git/ignore` if you do not want it tracked in your git remotes.

---

## Configuration

```lua
require("janus").setup({
  -- Name of the configuration dotfile
  filename = ".janus",

  -- Theme restored when leaving a repository or if no .janus is found.
  -- nil => the colorscheme / 'background' active the first time janus runs
  -- this session (survives a colorscheme plugin that loads after janus).
  default_colorscheme = nil,
  default_background = nil,

  -- When true, janus applies a .janus theme when it finds one but never
  -- reverts on leaving -- the last theme sticks until a different .janus,
  -- a manual :colorscheme, or :JanusReset changes it.
  sticky = false,

  -- Directory markers used to identify a project root when no .janus exists.
  root_markers = { ".git" },

  -- Suppress "loaded X" / "not found" notifications.
  silent = false,
})
```

### Commands

| Command                           | Description                                                                |
| --------------------------------- | -------------------------------------------------------------------------- |
| `:JanusSet {theme} [dark\|light]` | Write `.janus` for the current workspace and apply it immediately.         |
| `:JanusGet`                       | Show the workspace root, source file, and resolved colorscheme/background. |
| `:JanusReset`                     | Delete the workspace `.janus` and restore the default colorscheme.         |

---

## Roadmap

- [x] **v1.0:** Core declarative theme switching via `.janus` dotfiles.
- **v2.0:** Unlikely to ever happen. The plugin does the one thing I wanted which was to theme this repo, theme that folder, theme per repo. And it's essentially done here. The focus from here is maintenance and ironing out issues. I'm keeping it scoped to be spiritually similar to what I used Peacock in VS Code

The one thing I'd still consider is a per-repo transparency toggle, since that's well within scope. Custom highlight-group overrides are **not** planned, at that point you're better off making or installing a proper colorscheme and just pointing `.janus` at it.

There is a concern that I did note: `.janus` is a custom dotfile and in case there is another user besides me, you would need to remember to include this filetype in the gitignore, so do note that

> Note: It just occured to me that [carlhuda/janus](https://github.com/carlhuda/janus) also has the same name where in this case, its a distribution last updated circa ~10 years ago. If the name is a concern, let me know via git issue and I can explore it. I maintain that the name janus is appropriate for this usecase in any cases.

---

## License

MIT License © Bryan Lukehart-Yun

This code is free to use under the terms of the MIT License as desired following the terms and conditions listed.
