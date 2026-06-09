#!/usr/bin/env bash
# Plain-text command snippets with fzf.
# Source from bash or zsh:
#   . "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"
#
# Optional:
#   export SNIPPETS_FILE="$HOME/_snippets.txt"
#   export SNIPPETS_FZF_GLOBAL_TERMINAL="kitty --class snippets-fzf"
#   export SNIPPETS_AUTO_BIND=0
#   export SNIPPETS_PASTE_DELAY=0.25
#   export SNIPPETS_GUI_WAIT_TIMEOUT=300
#   export SNIPPETS_GUI_SELECTOR=rofi  # rofi, fzf, auto
#   export SNIPPETS_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh"
#   export SNIPPETS_BIN_DIR="$HOME/.local/bin"
#   export SNIPPETS_SYNC_SERVERS="host1 host2"
#   export SNIPPETS_AUTO_COMPLETE=0
#
# Interactive zsh/bash shells bind keys automatically by default.
# To re-bind manually after another plugin changed keys:
#   snippets_bind_keys
#
# Desktop/global hotkey command example:
#   zsh -lc '. "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"; snippets_fzf_gui_insert'

: "${SNIPPETS_FILE:=$HOME/_snippets.txt}"
: "${SNIPPETS_INSTALL_URL:=https://github.com/iskrantxusa/snippets-fzf.sh/raw/refs/heads/master/snippets-fzf.sh}"
: "${SNIPPETS_INSTALL_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh}"
: "${SNIPPETS_INSTALL_FILE:=$SNIPPETS_INSTALL_DIR/snippets-fzf.sh}"
: "${SNIPPETS_BIN_DIR:=$HOME/.local/bin}"
: "${SNIPPETS_BIN_FILE:=$SNIPPETS_BIN_DIR/snippets}"

if [ -n "${ZSH_VERSION-}" ]; then
  : "${SNIPPETS_LIB_FILE:=${${(%):-%x}:A}}"
elif [ -n "${BASH_VERSION-}" ]; then
  : "${SNIPPETS_LIB_FILE:=${BASH_SOURCE[0]}}"
else
  : "${SNIPPETS_LIB_FILE:=$HOME/_ai.snippets/snippets-fzf.sh}"
fi

snippets__need() {
  command -v "$1" >/dev/null 2>&1
}

snippets__ensure_file() {
  [ -n "$SNIPPETS_FILE" ] || return 1
  [ -e "$SNIPPETS_FILE" ] || : >"$SNIPPETS_FILE"
}

snippets__sha256() {
  if snippets__need sha256sum; then
    printf '%s' "$1" | sha256sum | awk '{ print $1 }'
  elif snippets__need shasum; then
    printf '%s' "$1" | shasum -a 256 | awk '{ print $1 }'
  elif snippets__need openssl; then
    printf '%s' "$1" | openssl dgst -sha256 -r | awk '{ print $1 }'
  else
    printf 'snippets: sha256sum, shasum, or openssl is required\n' >&2
    return 127
  fi
}

snippets__deleted_record() {
  hash=$(snippets__sha256 "$1") || return 1
  printf 'DELETED:sha256(%s)\n' "$hash"
}

snippets__is_deleted_record() {
  printf '%s\n' "$1" | grep -Eq '^DELETED:sha256\([0-9a-fA-F]{64}\)$'
}

snippets__deleted_hashes() {
  snippets__ensure_file || return 1
  awk '
    /^DELETED:sha256\([0-9a-fA-F]{64}\)$/ {
      value = $0
      sub(/^DELETED:sha256\(/, "", value)
      sub(/\)$/, "", value)
      print tolower(value)
    }
  ' "$SNIPPETS_FILE"
}

snippets__is_tombstoned_text() {
  hash=$(snippets__sha256 "$1") || return 1
  snippets__deleted_hashes | grep -Fxiq -- "$hash"
}

snippets__normalize_files() {
  tomb=${TMPDIR:-/tmp}/snippets-tomb.$$
  unique=${TMPDIR:-/tmp}/snippets-unique.$$

  awk '
    /^DELETED:sha256\([0-9a-fA-F]{64}\)$/ {
      value = $0
      sub(/^DELETED:sha256\(/, "", value)
      sub(/\)$/, "", value)
      print tolower(value)
    }
  ' "$@" | awk '!seen[$0]++' >"$tomb" || {
    rm -f "$tomb" "$unique"
    return 1
  }

  awk '!seen[$0]++' "$@" >"$unique" || {
    rm -f "$tomb" "$unique"
    return 1
  }

  while IFS= read -r line || [ -n "$line" ]; do
    if snippets__is_deleted_record "$line"; then
      hash=${line#DELETED:sha256(}
      hash=${hash%)}
      hash=$(printf '%s' "$hash" | tr '[:upper:]' '[:lower:]')
      printf 'DELETED:sha256(%s)\n' "$hash"
      continue
    fi

    case "$line" in
      '' | \#*) printf '%s\n' "$line"; continue ;;
    esac

    hash=$(snippets__sha256 "$line") || {
      rm -f "$tomb" "$unique"
      return 1
    }
    if grep -Fxiq -- "$hash" "$tomb"; then
      continue
    fi
    printf '%s\n' "$line"
  done <"$unique" | awk '!seen[$0]++'

  rm -f "$tomb" "$unique"
}

snippets__print_snippets() {
  snippets__ensure_file || return 1
  snippets__normalize_files "$SNIPPETS_FILE" |
    awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      /^DELETED:sha256\([0-9a-fA-F]{64}\)$/ { next }
      { print }
    '
}

snippets__print_history() {
  if [ -n "${ZSH_VERSION-}" ]; then
    fc -ln 1 2>/dev/null
    return
  fi

  if [ -n "${BASH_VERSION-}" ]; then
    history | sed 's/^[[:space:]]*[0-9][0-9]*[[:space:]]*//'
    return
  fi

  if [ -n "${HISTFILE-}" ] && [ -r "$HISTFILE" ]; then
    sed 's/^: [0-9][0-9]*:[0-9]*;//' "$HISTFILE"
  fi
}

snippets__print_history_files() {
  if [ -n "${ZDOTDIR-}" ] && [ -r "$ZDOTDIR/.zsh_history" ]; then
    sed 's/^: [0-9][0-9]*:[0-9]*;//' "$ZDOTDIR/.zsh_history"
  elif [ -r "$HOME/.zsh_history" ]; then
    sed 's/^: [0-9][0-9]*:[0-9]*;//' "$HOME/.zsh_history"
  fi

  if [ -r "$HOME/.bash_history" ]; then
    cat "$HOME/.bash_history"
  fi
}

snippets__print_all() {
  {
    snippets__print_history
    snippets__print_snippets
  } | awk '!seen[$0]++'
}

snippets__print_all_for_gui() {
  {
    snippets__print_history_files
    snippets__print_snippets
  } | awk 'NF && !seen[$0]++'
}

snippets__choose_all() {
  snippets__print_all |
    fzf --tac --tiebreak=index --bind=ctrl-r:toggle-sort --query="${1-}" +m
}

snippets__choose_history() {
  snippets__print_history |
    awk 'NF && !seen[$0]++' |
    fzf --tac --tiebreak=index --bind=ctrl-r:toggle-sort +m
}

snippets_add() {
  snippets__ensure_file || return 1
  [ "$#" -gt 0 ] || return 1
  if snippets__is_tombstoned_text "$*"; then
    printf 'snippets: deleted tombstone exists, refusing to re-add: %s\n' "$*" >&2
    return 1
  fi
  printf '%s\n' "$*" >>"$SNIPPETS_FILE"
}

snippets_status() {
  snippets__ensure_file || return 1
  printf 'SNIPPETS_FILE=%s\n' "$SNIPPETS_FILE"
  printf 'snippet_lines=%s\n' "$(snippets__print_snippets | wc -l | tr -d ' ')"
  if [ -n "${ZSH_VERSION-}" ]; then
    bindkey '^R' 2>/dev/null || true
    zle -l 2>/dev/null | grep -Fx snippets_zle_insert >/dev/null &&
      printf 'zle_widget=snippets_zle_insert\n' ||
      printf 'zle_widget=missing\n'
  fi
}

snippets__ssh_hosts() {
  if [ -n "${SNIPPETS_SYNC_SERVERS-}" ]; then
    printf '%s\n' $SNIPPETS_SYNC_SERVERS
    return
  fi

  [ -r "$HOME/.ssh/config" ] || return 0

  awk '
    tolower($1) == "host" {
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^#/) {
          break
        }
        if ($i !~ /[*?!]/) {
          print $i
        }
      }
    }
  ' "$HOME/.ssh/config" | awk '!seen[$0]++'
}

snippets_sync_one() {
  server=$1
  tmp=${TMPDIR:-/tmp}/snippets-sync.$$
  remote_tmp=${TMPDIR:-/tmp}/snippets-sync-remote.$$

  snippets__ensure_file || return 1
  [ -n "$server" ] || {
    printf 'snippets: missing server\n' >&2
    return 2
  }

  printf 'snippets: merging %s with %s:~/_snippets.txt\n' "$SNIPPETS_FILE" "$server"
  if ! ssh "$server" 'cat "$HOME/_snippets.txt" 2>/dev/null || true' >"$remote_tmp"; then
    rm -f "$tmp" "$remote_tmp"
    return 1
  fi

  snippets__normalize_files "$SNIPPETS_FILE" "$remote_tmp" >"$tmp" || {
    rm -f "$tmp" "$remote_tmp"
    return 1
  }

  cat "$tmp" >"$SNIPPETS_FILE" || {
    rm -f "$tmp" "$remote_tmp"
    return 1
  }

  if ! snippets_sync_push_one "$server" "$tmp"; then
    rm -f "$tmp" "$remote_tmp"
    return 1
  fi

  rm -f "$tmp" "$remote_tmp"
}

snippets_sync_push_one() {
  server=$1
  file=${2:-$SNIPPETS_FILE}

  ssh "$server" 'cat > "$HOME/_snippets.txt"' <"$file"
}

snippets_sync() {
  snippets__ensure_file || return 1
  snippets__need ssh || {
    printf 'snippets: ssh not found\n' >&2
    return 127
  }

  if [ "$#" -gt 1 ]; then
    printf 'snippets: usage: snippets sync [server]\n' >&2
    return 2
  fi

  if [ "$#" -eq 1 ]; then
    snippets_sync_one "$1"
    return
  fi

  servers=$(snippets__ssh_hosts)
  if [ -z "$servers" ]; then
    printf 'snippets: no SSH hosts found in ~/.ssh/config\n' >&2
    printf 'snippets: set SNIPPETS_SYNC_SERVERS="host1 host2" or run snippets sync <server>\n' >&2
    return 1
  fi

  printf 'Are you sure you want to sync your snippets to all SSH hosts available from ~/.ssh/config? [y/N] ' >&2
  read -r answer
  case "$answer" in
    y | Y | yes | YES)
      ;;
    *)
      printf 'snippets: sync cancelled\n' >&2
      return 1
      ;;
  esac

  failed=0
  for server in $servers; do
    snippets_sync_one "$server" || failed=$((failed + 1))
  done
  for server in $servers; do
    snippets_sync_push_one "$server" || failed=$((failed + 1))
  done

  if [ "$failed" -gt 0 ]; then
    printf 'snippets: sync finished with %s failure(s)\n' "$failed" >&2
    return 1
  fi

  printf 'snippets: sync finished\n'
}

snippets_save_from_history() {
  snippets__need fzf || {
    printf 'snippets: fzf not found\n' >&2
    return 127
  }

  selected=$(snippets__choose_history) || return
  [ -n "$selected" ] || return

  snippets__ensure_file || return 1
  if grep -Fxq -- "$selected" "$SNIPPETS_FILE" 2>/dev/null; then
    printf 'snippets: already saved: %s\n' "$selected" >&2
  elif snippets__is_tombstoned_text "$selected"; then
    printf 'snippets: deleted tombstone exists, refusing to save: %s\n' "$selected" >&2
    return 1
  else
    printf '%s\n' "$selected" >>"$SNIPPETS_FILE"
    printf '\033[32m[OK]\033[0m snippets: saved: %s\n' "$selected" >&2
  fi
}

snippets_delete() {
  snippets__need fzf || {
    printf 'snippets: fzf not found\n' >&2
    return 127
  }

  selected=$(snippets__print_snippets | fzf --tac --tiebreak=index --prompt='delete> ' +m) || return
  [ -n "$selected" ] || return

  record=$(snippets__deleted_record "$selected") || return 1
  if ! grep -Fxqi -- "$record" "$SNIPPETS_FILE" 2>/dev/null; then
    printf '%s\n' "$record" >>"$SNIPPETS_FILE"
  fi

  tmp=${TMPDIR:-/tmp}/snippets-delete.$$
  snippets__normalize_files "$SNIPPETS_FILE" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  cat "$tmp" >"$SNIPPETS_FILE"
  rm -f "$tmp"
  printf '\033[32m[OK]\033[0m snippets: deleted: %s\n' "$selected" >&2
}

snippets_prune_deleted() {
  snippets__ensure_file || return 1
  printf 'Are you sure you want to remove local DELETED tombstones? [y/N] ' >&2
  read -r answer
  case "$answer" in
    y | Y | yes | YES) ;;
    *)
      printf 'snippets: prune cancelled\n' >&2
      return 1
      ;;
  esac

  tmp=${TMPDIR:-/tmp}/snippets-prune.$$
  grep -Evi '^DELETED:sha256\([0-9a-f]{64}\)$' "$SNIPPETS_FILE" >"$tmp" || true
  cat "$tmp" >"$SNIPPETS_FILE"
  rm -f "$tmp"
  printf '\033[32m[OK]\033[0m snippets: pruned deleted tombstones\n' >&2
}

snippets_bash_complete() {
  local cur prev commands hosts

  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD - 1]}
  commands='sync delete prune-deleted help --help -h --install'

  case "$prev" in
    sync)
      hosts=$(snippets__ssh_hosts)
      mapfile -t COMPREPLY < <(compgen -W "$hosts" -- "$cur")
      ;;
    snippets)
      mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
      ;;
  esac
}

snippets_zsh_complete() {
  local -a commands hosts

  commands=(sync delete prune-deleted help --help -h --install)
  if (( CURRENT == 2 )); then
    _describe 'snippets command' commands
  elif [[ ${words[2]} == sync ]]; then
    hosts=(${(f)"$(snippets__ssh_hosts)"})
    _describe 'ssh host' hosts
  fi
}

snippets_register_completion() {
  case "${SNIPPETS_AUTO_COMPLETE:-1}" in
    0 | false | FALSE | no | NO)
      if [ -n "${BASH_VERSION-}" ]; then
        complete -r snippets 2>/dev/null || true
      fi
      return
      ;;
  esac

  if [ -n "${BASH_VERSION-}" ]; then
    complete -F snippets_bash_complete snippets 2>/dev/null || true
  elif [ -n "${ZSH_VERSION-}" ]; then
    if command -v compdef >/dev/null 2>&1; then
      compdef snippets_zsh_complete snippets 2>/dev/null || true
    fi
  fi
}

snippets_fzf_gui_select() {
  snippets__need fzf || {
    printf 'snippets: fzf not found\n' >&2
    return 127
  }

  snippets__print_all_for_gui |
    fzf --tac --tiebreak=index --bind=ctrl-r:toggle-sort --prompt='cmd> ' +m
}

snippets_rofi_gui_select() {
  snippets__need rofi || {
    printf 'snippets: rofi not found\n' >&2
    return 127
  }

  snippets__print_all_for_gui |
    rofi -dmenu -i -p 'cmd'
}

snippets_gui_select() {
  case "${SNIPPETS_GUI_SELECTOR:-auto}" in
    rofi)
      snippets_rofi_gui_select
      ;;
    fzf)
      snippets_fzf_gui_select
      ;;
    auto | '')
      if snippets__need rofi; then
        snippets_rofi_gui_select
      else
        snippets_fzf_gui_select
      fi
      ;;
    *)
      printf 'snippets: unknown SNIPPETS_GUI_SELECTOR=%s\n' "$SNIPPETS_GUI_SELECTOR" >&2
      return 2
      ;;
  esac
}

snippets__copy_clipboard() {
  if [ -n "${DISPLAY-}" ]; then
    if snippets__need xclip && xclip -selection clipboard; then
      return 0
    fi
    if snippets__need xsel && xsel --clipboard --input; then
      return 0
    fi
  fi

  if [ -n "${WAYLAND_DISPLAY-}" ] && snippets__need wl-copy && wl-copy; then
    return 0
  fi

  if snippets__need xclip && xclip -selection clipboard; then
    return 0
  fi
  if snippets__need xsel && xsel --clipboard --input; then
    return 0
  fi
  if snippets__need wl-copy && wl-copy; then
    return 0
  fi

  return 127
}

snippets__paste_clipboard() {
  if [ -n "${WAYLAND_DISPLAY-}" ] && snippets__need wtype; then
    wtype -M ctrl v -m ctrl
  elif snippets__need xdotool; then
    if [ -n "${1-}" ]; then
      xdotool windowactivate --sync "$1"
      sleep "${SNIPPETS_PASTE_DELAY:-0.25}"
      xdotool key --clearmodifiers ctrl+v
    else
      xdotool key --clearmodifiers ctrl+v
    fi
  else
    return 127
  fi
}

snippets__pick_terminal() {
  if [ -n "${SNIPPETS_FZF_GLOBAL_TERMINAL-}" ]; then
    printf '%s\n' 'custom'
  elif snippets__need kitty; then
    printf '%s\n' 'kitty'
  elif snippets__need alacritty; then
    printf '%s\n' 'alacritty'
  elif snippets__need foot; then
    printf '%s\n' 'foot'
  elif snippets__need gnome-terminal; then
    printf '%s\n' 'gnome-terminal --'
  elif snippets__need xterm; then
    printf '%s\n' 'xterm -e'
  else
    return 127
  fi
}

snippets__run_gui_selector() {
  case "$1" in
    custom)
      eval "SNIPPETS_FZF_OUT=\$tmp SNIPPETS_FZF_DONE=\$done_file SNIPPETS_LIB_FILE=\$SNIPPETS_LIB_FILE $SNIPPETS_FZF_GLOBAL_TERMINAL sh -c '. \"\$SNIPPETS_LIB_FILE\"; snippets_gui_select >\"\$SNIPPETS_FZF_OUT\"; : >\"\$SNIPPETS_FZF_DONE\"'"
      ;;
    kitty)
      SNIPPETS_FZF_OUT=$tmp SNIPPETS_FZF_DONE=$done_file SNIPPETS_LIB_FILE=$SNIPPETS_LIB_FILE \
        kitty sh -c '. "$SNIPPETS_LIB_FILE"; snippets_gui_select >"$SNIPPETS_FZF_OUT"; : >"$SNIPPETS_FZF_DONE"'
      ;;
    alacritty)
      SNIPPETS_FZF_OUT=$tmp SNIPPETS_FZF_DONE=$done_file SNIPPETS_LIB_FILE=$SNIPPETS_LIB_FILE \
        alacritty -e sh -c '. "$SNIPPETS_LIB_FILE"; snippets_gui_select >"$SNIPPETS_FZF_OUT"; : >"$SNIPPETS_FZF_DONE"'
      ;;
    foot)
      SNIPPETS_FZF_OUT=$tmp SNIPPETS_FZF_DONE=$done_file SNIPPETS_LIB_FILE=$SNIPPETS_LIB_FILE \
        foot sh -c '. "$SNIPPETS_LIB_FILE"; snippets_gui_select >"$SNIPPETS_FZF_OUT"; : >"$SNIPPETS_FZF_DONE"'
      ;;
    gnome-terminal*)
      SNIPPETS_FZF_OUT=$tmp SNIPPETS_FZF_DONE=$done_file SNIPPETS_LIB_FILE=$SNIPPETS_LIB_FILE \
        gnome-terminal -- sh -c '. "$SNIPPETS_LIB_FILE"; snippets_gui_select >"$SNIPPETS_FZF_OUT"; : >"$SNIPPETS_FZF_DONE"'
      ;;
    xterm*)
      SNIPPETS_FZF_OUT=$tmp SNIPPETS_FZF_DONE=$done_file SNIPPETS_LIB_FILE=$SNIPPETS_LIB_FILE \
        xterm -e sh -c '. "$SNIPPETS_LIB_FILE"; snippets_gui_select >"$SNIPPETS_FZF_OUT"; : >"$SNIPPETS_FZF_DONE"'
      ;;
  esac
}

snippets_fzf_gui_insert() {
  tmp=${TMPDIR:-/tmp}/snippets-fzf-selected.$$
  done_file=${TMPDIR:-/tmp}/snippets-fzf-done.$$
  active_window=

  if snippets__need xdotool; then
    active_window=$(xdotool getactivewindow 2>/dev/null || :)
  fi

  if [ "${SNIPPETS_GUI_SELECTOR:-auto}" != fzf ] && snippets__need rofi; then
    snippets_rofi_gui_select >"$tmp"
  else
    terminal=$(snippets__pick_terminal) || {
      printf 'snippets: no supported terminal found\n' >&2
      return 127
    }

    snippets__run_gui_selector "$terminal"

    waited_ticks=0
    wait_limit_ticks=$((${SNIPPETS_GUI_WAIT_TIMEOUT:-300} * 10))
    while [ ! -e "$done_file" ] && [ "$waited_ticks" -lt "$wait_limit_ticks" ]; do
      sleep 0.1
      waited_ticks=$((waited_ticks + 1))
    done
  fi

  if [ -s "$tmp" ]; then
    snippets__copy_clipboard <"$tmp" || {
      rm -f "$tmp" "$done_file"
      printf 'snippets: no clipboard tool found; install wl-copy, xclip, or xsel\n' >&2
      return 127
    }
    sleep "${SNIPPETS_PASTE_DELAY:-0.25}"
    snippets__paste_clipboard "$active_window" || {
      rm -f "$tmp" "$done_file"
      printf 'snippets: no paste tool found; install wtype or xdotool\n' >&2
      return 127
    }
  fi

  rm -f "$tmp" "$done_file"
}

if [ -n "${ZSH_VERSION-}" ]; then
  snippets_zle_insert() {
    local selected
    selected=$(snippets__choose_all "$LBUFFER") || return
    BUFFER="${selected}"
    CURSOR=${#BUFFER}
    zle redisplay 2>/dev/null || true
  }

  snippets_zle_save_from_history() {
    snippets_save_from_history
    zle redisplay 2>/dev/null || true
  }

  snippets_bind_keys() {
    zle -N snippets_zle_insert
    zle -N snippets_zle_save_from_history
    bindkey '^R' snippets_zle_insert
    bindkey '^[s' snippets_zle_save_from_history
  }

  if [[ -o interactive && "${SNIPPETS_AUTO_BIND:-1}" != 0 ]]; then
    snippets_bind_keys
  fi
  if [[ -o interactive ]]; then
    snippets_register_completion
  fi
elif [ -n "${BASH_VERSION-}" ]; then
  snippets_bash_insert() {
    local selected
    selected=$(snippets__choose_all "$READLINE_LINE") || return
    READLINE_LINE=$selected
    READLINE_POINT=${#READLINE_LINE}
  }

  snippets_bind_keys() {
    bind -x '"\C-r": snippets_bash_insert'
    bind -x '"\es": snippets_save_from_history'
  }

  case $- in
    *i*)
      if [ "${SNIPPETS_AUTO_BIND:-1}" != 0 ]; then
        snippets_bind_keys
      fi
      snippets_register_completion
      ;;
  esac
fi

snippets__script_path() {
  source_path=
  if [ -n "${SNIPPETS_LIB_FILE-}" ] && [ -f "$SNIPPETS_LIB_FILE" ]; then
    source_path=$SNIPPETS_LIB_FILE
  else
    source_path=$0
  fi

  case "$source_path" in
    '' | - | bash | sh | zsh) return 1 ;;
  esac

  case "$source_path" in
    /*) printf '%s\n' "$source_path" ;;
    */*)
      source_dir=${source_path%/*}
      source_base=${source_path##*/}
      printf '%s/%s\n' "$(cd "$source_dir" 2>/dev/null && pwd -P)" "$source_base"
      ;;
    *) command -v "$source_path" ;;
  esac
}

snippets__is_local_script_path() {
  [ -n "${1-}" ] || return 1
  [ -f "$1" ] || return 1
  case "$1" in
    - | bash | sh | zsh) return 1 ;;
  esac
}

snippets__shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

snippets__download() {
  url=$1
  target=$2

  if snippets__need curl; then
    curl -fsSL "$url" -o "$target"
  elif snippets__need wget; then
    wget -qO "$target" "$url"
  else
    printf 'snippets: curl or wget is required for pipe install\n' >&2
    return 127
  fi
}

snippets__install_script_file() {
  source_path=$1

  mkdir -p "$SNIPPETS_INSTALL_DIR" || return 1

  if snippets__is_local_script_path "$source_path"; then
    source_path=$(cd "${source_path%/*}" 2>/dev/null && pwd -P)/${source_path##*/}
    if [ "$source_path" != "$SNIPPETS_INSTALL_FILE" ]; then
      cp "$source_path" "$SNIPPETS_INSTALL_FILE" || return 1
    fi
  else
    snippets__download "$SNIPPETS_INSTALL_URL" "$SNIPPETS_INSTALL_FILE" || return 1
  fi

  chmod +x "$SNIPPETS_INSTALL_FILE" || return 1
  printf 'snippets: installed script at %s\n' "$SNIPPETS_INSTALL_FILE"
}

snippets__install_bin_wrapper() {
  quoted_target=$(snippets__shell_quote "$SNIPPETS_INSTALL_FILE")

  mkdir -p "$SNIPPETS_BIN_DIR" || return 1
  {
    printf '#!/usr/bin/env sh\n'
    printf 'exec %s "$@"\n' "$quoted_target"
  } >"$SNIPPETS_BIN_FILE" || return 1
  chmod +x "$SNIPPETS_BIN_FILE" || return 1
  printf 'snippets: installed command at %s\n' "$SNIPPETS_BIN_FILE"
}

snippets__append_install_block() {
  target=$1
  script_path=$2
  marker='snippets-fzf.sh'

  touch "$target" || return 1

  if grep -Fq "$script_path" "$target" 2>/dev/null ||
    grep -Fq "# ${marker} begin" "$target" 2>/dev/null; then
    printf 'snippets: already installed in %s\n' "$target"
    return 0
  fi

  {
    printf '\n# %s begin\n' "$marker"
    printf 'if [ -f %s ]; then\n' "'$script_path'"
    printf '  . %s\n' "'$script_path'"
    printf 'fi\n'
    printf '# %s end\n' "$marker"
  } >>"$target"

  printf 'snippets: installed in %s\n' "$target"
}

snippets__zshrc_includes_local() {
  zshrc=$HOME/.zshrc
  [ -r "$zshrc" ] || return 1

  grep -Eq '(^|[;&[:space:]])(\.|source)[[:space:]]+("?)(~|\$HOME|'"$HOME"')/\.zshrc\.local\3([;&[:space:]]|$)' "$zshrc"
}

snippets_install() {
  script_path=$(snippets__script_path)
  snippets__install_script_file "$script_path" || return 1
  snippets__install_bin_wrapper || return 1
  snippets__append_install_block "$HOME/.zshrc.local" "$SNIPPETS_INSTALL_FILE" || return 1
  snippets__append_install_block "$HOME/.bashrc" "$SNIPPETS_INSTALL_FILE" || return 1

  if ! snippets__zshrc_includes_local; then
    red=$(printf '\033[31m')
    reset=$(printf '\033[0m')
    printf '%sWARNING:%s ~/.zshrc does not appear to include ~/.zshrc.local\n' "$red" "$reset" >&2
    printf 'Add it with:\n' >&2
    printf '%s\n' "printf '\n[ -f \"\$HOME/.zshrc.local\" ] && . \"\$HOME/.zshrc.local\"\n' >> ~/.zshrc" >&2
  fi
}

snippets_help() {
  cat <<'EOF'
snippets-fzf.sh - plain-text command snippets for bash/zsh

Usage:
  snippets-fzf.sh --help
  snippets-fzf.sh --install
  snippets sync [server]
  snippets delete
  snippets prune-deleted
  curl -fsSL https://github.com/iskrantxusa/snippets-fzf.sh/raw/refs/heads/master/snippets-fzf.sh | bash

Source from shell config:
  . "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"

Installed CLI:
  snippets --help
  snippets --install
  snippets sync [server]
  snippets delete
  snippets prune-deleted

Installed interactive bindings:
  Ctrl+R   search shell history + snippets and insert selected command
  Alt+s    save selected history command into $SNIPPETS_FILE

Useful functions:
  snippets_status
  snippets_add <command>
  snippets_save_from_history
  snippets_fzf_gui_insert
  snippets_sync [server]
  snippets_delete
  snippets_prune_deleted

Files and knobs:
  SNIPPETS_FILE=$HOME/_snippets.txt
  SNIPPETS_INSTALL_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh
  SNIPPETS_BIN_FILE=$HOME/.local/bin/snippets
  SNIPPETS_SYNC_SERVERS="host1 host2"
  SNIPPETS_AUTO_COMPLETE=1
  SNIPPETS_GUI_SELECTOR=auto   # auto, rofi, fzf
  SNIPPETS_PASTE_DELAY=0.25
  SNIPPETS_AUTO_BIND=1

Global hotkey command example:
  zsh -lc '. "${XDG_DATA_HOME:-$HOME/.local/share}/snippets-fzf.sh/snippets-fzf.sh"; snippets_fzf_gui_insert'
EOF
}

snippets__is_sourced() {
  if [ -n "${BASH_VERSION-}" ]; then
    [ "${BASH_SOURCE[0]}" = main ] && return 1
    [ "${BASH_SOURCE[0]}" != "$0" ]
    return
  fi

  if [ -n "${ZSH_VERSION-}" ]; then
    case "${ZSH_EVAL_CONTEXT-}" in
      *:file | *:file:*) return 0 ;;
    esac
    return 1
  fi

  return 1
}

if ! snippets__is_sourced; then
  if [ "$#" -eq 0 ] && [ ! -t 0 ] &&
    ! snippets__is_local_script_path "$(snippets__script_path)"; then
    snippets_install
    exit $?
  fi

  case "${1---help}" in
    --install)
      snippets_install
      ;;
    sync)
      shift
      snippets_sync "$@"
      ;;
    delete)
      shift
      snippets_delete "$@"
      ;;
    prune-deleted)
      shift
      snippets_prune_deleted "$@"
      ;;
    --help | -h | help)
      snippets_help
      ;;
    *)
      snippets_help >&2
      exit 2
      ;;
  esac
fi
