# snippets-fzf.sh

Plain-text command snippets for Bash and Zsh, searchable with `fzf`, `rofi`, and your shell history.

The idea is deliberately boring: keep useful commands in one text file, sync it with Git or your dotfiles, and make those commands available from the terminal and from a global desktop hotkey.

## Features

- Stores snippets in a plain text file: `~/_snippets.txt` by default.
- Searches shell history and snippets together.
- Replaces the current shell command line from `Ctrl+R`.
- Saves an existing history command into the snippets file with a hotkey.
- Supports Bash and Zsh from the same script.
- Provides a GUI picker for global desktop hotkeys.
- Uses `rofi -dmenu` for GUI selection when available, with a terminal + `fzf` fallback.
- Works well with Git-based syncing because the snippet database is just text.

## Requirements

Core:

- Bash or Zsh
- `fzf`
- `awk`, `sed`, `grep`

Optional GUI picker:

- `rofi` for the recommended GUI menu
- or a terminal emulator: `kitty`, `alacritty`, `foot`, `gnome-terminal`, or `xterm`

Optional paste support for global hotkeys:

- X11: `xdotool` plus `xclip` or `xsel`
- Wayland: `wtype` plus `wl-copy`

## Installation

Recommended one-line install:

```sh
curl -fsSL https://github.com/iskrantxusa/snippets-fzf.sh/raw/refs/heads/master/snippets-fzf.sh | bash
```

This installs:

- sourceable shell integration: `~/.local/share/snippets-fzf.sh/snippets-fzf.sh`
- CLI wrapper: `~/.local/bin/snippets`
- shell config blocks in `~/.zshrc.local` and `~/.bashrc`

Make sure `~/.local/bin` is in your `PATH` if you want to run the CLI as `snippets`.

You can also clone the repository manually:

```sh
git clone https://github.com/iskrantxusa/snippets-fzf.sh.git ~/.local/share/snippets-fzf.sh
cd ~/.local/share/snippets-fzf.sh
```

Run the installer:

```sh
./snippets-fzf.sh --install
```

The installer copies the script to the install location, creates the `snippets` wrapper, and appends a small source block to:

- `~/.zshrc.local`
- `~/.bashrc`

For Zsh it also checks whether `~/.zshrc` includes `~/.zshrc.local`. If not, it prints the command needed to add that include.

Manual installation is also fine:

```sh
. "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"
```

Put that line near the end of `~/.zshrc.local` or `~/.bashrc`, especially if other shell plugins also bind `Ctrl+R`.

## Snippets File

By default snippets are read from:

```sh
~/_snippets.txt
```

Each non-empty, non-comment line is one command:

```text
docker system df
docker system prune -a -f --volumes # remove unused Docker data
git reset HEAD~1 # undo last commit, keep changes
curl -I https://example.com
```

Blank lines and lines beginning with `#` are ignored.

To use another file:

```sh
export SNIPPETS_FILE="$HOME/.config/snippets/commands.txt"
. ~/.local/share/snippets-fzf.sh/snippets-fzf.sh
```

If you sync dotfiles with Git, a useful pattern is:

```sh
ln -s ~/.config/snippets/commands.txt ~/_snippets.txt
```

## Key Bindings

Bindings are installed automatically when the script is sourced in an interactive Bash or Zsh shell.

| Binding | Action |
| --- | --- |
| `Ctrl+R` | Search shell history and snippets, then insert the selected command into the current command line |
| `Alt+s` | Pick a command from shell history and append it to `SNIPPETS_FILE` |

If another plugin overwrites the bindings, call this after all plugins:

```sh
snippets_bind_keys
```

To disable automatic binding:

```sh
export SNIPPETS_AUTO_BIND=0
. ~/.local/share/snippets-fzf.sh/snippets-fzf.sh
```

Then bind manually with your own shell setup.

## GUI Picker

The GUI picker is meant for a global desktop shortcut. It lets you choose from snippets and history outside the terminal and paste the selected command into the currently focused window.

Command for your window manager or desktop environment:

```sh
zsh -lc '. "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"; snippets_fzf_gui_insert'
```

Despite the function name, the GUI picker can use either `rofi` or `fzf`.

Selection backend:

```sh
export SNIPPETS_GUI_SELECTOR=auto  # default: rofi if installed, otherwise fzf
export SNIPPETS_GUI_SELECTOR=rofi  # force rofi -dmenu
export SNIPPETS_GUI_SELECTOR=fzf   # force terminal + fzf
```

When `rofi` is installed, the picker uses:

```sh
snippets__print_all_for_gui | rofi -dmenu -i -p 'cmd'
```

If `rofi` is not available, it opens a terminal window and runs `fzf` there.

### Paste Timing

Some window managers need a small delay after the picker closes before receiving `Ctrl+V`.

Default:

```sh
export SNIPPETS_PASTE_DELAY=0.25
```

If selection works but paste is unreliable, try:

```sh
export SNIPPETS_PASTE_DELAY=0.5
```

## Commands

Show status:

```sh
snippets_status
```

Add a snippet directly:

```sh
snippets_add 'git log --oneline --decorate --graph --all'
```

Save a command from history:

```sh
snippets_save_from_history
```

Open the GUI picker and paste the selected command:

```sh
snippets_fzf_gui_insert
```

Show script help:

```sh
snippets --help
```

Re-run install or update shell integration:

```sh
snippets --install
```

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `SNIPPETS_FILE` | `$HOME/_snippets.txt` | Plain-text snippets file |
| `SNIPPETS_INSTALL_DIR` | `${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh` | Where the sourceable script is installed |
| `SNIPPETS_BIN_FILE` | `$HOME/.local/bin/snippets` | CLI wrapper path |
| `SNIPPETS_AUTO_BIND` | `1` | Automatically bind keys in interactive shells |
| `SNIPPETS_GUI_SELECTOR` | `auto` | `auto`, `rofi`, or `fzf` |
| `SNIPPETS_FZF_GLOBAL_TERMINAL` | auto-detected | Custom terminal command for the fzf GUI fallback |
| `SNIPPETS_PASTE_DELAY` | `0.25` | Delay before sending paste keystroke |
| `SNIPPETS_GUI_WAIT_TIMEOUT` | `300` | Timeout in seconds while waiting for fzf GUI fallback |

Example:

```sh
export SNIPPETS_FILE="$HOME/_config/_snippets.txt"
export SNIPPETS_GUI_SELECTOR=rofi
export SNIPPETS_PASTE_DELAY=0.5
. "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"
```

## Troubleshooting

Check what file is being used and whether Zsh widgets are registered:

```sh
snippets_status
```

If `Ctrl+R` does not use snippets, make sure the script is sourced after other history/fzf plugins:

```sh
snippets_bind_keys
```

If GUI selection works but paste does not:

- On X11, install `xdotool` and `xclip` or `xsel`.
- On Wayland, install `wtype` and `wl-copy`.
- Increase `SNIPPETS_PASTE_DELAY`.

If `rofi` is installed but you want the old terminal picker:

```sh
export SNIPPETS_GUI_SELECTOR=fzf
```

## Design

This script follows the Unix way:

- plain text for data
- small tools for selection and paste
- Git for sync
- shell functions instead of a daemon

No database, no background service, no custom file format.
