#!/usr/bin/env bash
#
# tmux-qweather.tmux - Tmux Plugin Manager (TPM) entry point for tmux-qweather
#

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${CURRENT_DIR}/scripts/weather.sh"

interpolate_option() {
  local option="$1"
  local val
  val="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
  local updated="$val"
  if [[ "$updated" == *'#{weather}'* ]]; then
    updated="${updated//\#\{weather\}/#(${SCRIPT_PATH})}"
  fi
  if [[ "$updated" == *'#{weather_icon}'* ]]; then
    updated="${updated//\#\{weather_icon\}/#(${SCRIPT_PATH} icon)}"
  fi
  if [[ "$updated" == *'#{weather_temp}'* ]]; then
    updated="${updated//\#\{weather_temp\}/#(${SCRIPT_PATH} temp)}"
  fi
  if [[ "$updated" == *'#{weather_condition}'* ]]; then
    updated="${updated//\#\{weather_condition\}/#(${SCRIPT_PATH} condition)}"
  fi
  if [[ "$updated" != "$val" ]]; then
    tmux set-option -gq "$option" "$updated"
  fi
}

bind_mouse() {
  local menu_cmd="run-shell -b '${SCRIPT_PATH} menu \"#{client_name}\" \"#{mouse_x}\"'"
  tmux bind-key -T root MouseDown1Status if-shell -F "#{==:#{mouse_status_range},weather}" \
    "$menu_cmd" "switch-client -t =" 2>/dev/null || true
  tmux bind-key -T root MouseDown1StatusRight if-shell -F "#{==:#{mouse_status_range},weather}" \
    "$menu_cmd" 2>/dev/null || true
  tmux bind-key -T root MouseDown3StatusRight if-shell -F "#{==:#{mouse_status_range},weather}" \
    "$menu_cmd" 2>/dev/null || true
}

main() {
  interpolate_option "status-right"
  interpolate_option "status-left"
  bind_mouse
}

main
