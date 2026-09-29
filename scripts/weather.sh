#!/usr/bin/env bash
#
# scripts/weather.sh - QWeather component with multi-city support and clickable menu.
#

set -euo pipefail

export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-qweather"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-qweather"
readonly WEATHER_CACHE_FILE="${CACHE_DIR}/weather_cache.json"
readonly DAILY_CACHE_FILE="${CACHE_DIR}/daily_cache.json"
readonly HOURLY_CACHE_FILE="${CACHE_DIR}/hourly_cache.json"
readonly LOCK_FILE="${CACHE_DIR}/refresh.lock"

declare -A COMPASS=([n]=北风 [nne]=东北偏北风 [ne]=东北风 [ene]=东北偏东风 [e]=东风 [ese]=东南偏东风 [se]=东南风 [sse]=东南偏南风 [s]=南风 [ssw]=西南偏南风 [sw]=西南风 [wsw]=西南偏西风 [w]=西风 [wnw]=西北偏西风 [nw]=西北风 [nnw]=西北偏北风)
declare -A MOON=([新月]=󰽤 [蛾眉月]=󰽥 [上弦月]=󰽦 [盈凸月]=󰽧 [满月]=󰽢 [望月]=󰽢 [亏凸月]=󰽨 [下弦月]=󰽩 [残月]=󰽪)

QWEATHER_HOST="devapi.qweather.com"
QWEATHER_KEY=""
CURRENT_CITY="北京"

ensure_config() {
  mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
  [[ -f "$CONFIG_FILE" ]] && return 0
  cat <<'CFG' > "$CONFIG_FILE"
{
  "key": "",
  "host": "devapi.qweather.com",
  "current": "北京",
  "locations": {
    "北京": "39.9042,116.4074"
  }
}
CFG
}

load_config() {
  ensure_config
  local cfg; cfg="$(<"$CONFIG_FILE")" 2>/dev/null || cfg="{}"
  QWEATHER_KEY="$(jq -r '.key // empty' <<<"$cfg")"
  QWEATHER_HOST="$(jq -r '.host // "devapi.qweather.com"' <<<"$cfg")"
  CURRENT_CITY="$(jq -r '.current // (.locations | keys[0] // "北京")' <<<"$cfg")"
}

weather_icon() {
  local code="${1:-}" text="${2:-}"
  case "$code" in
    100) printf '󰖙' ;; 10[1-3]) printf '󰖕' ;; 104) printf '󰖐' ;;
    30[01]) printf '󰖓' ;; 3*) printf '󰖗' ;; 4*) printf '󰼶' ;; 5*) printf '󰖑' ;;
    *)
      case "$text" in
        *晴*) printf '󰖙' ;; *多云*|*少云*) printf '󰖕' ;; *阴*) printf '󰖐' ;;
        *雷*) printf '󰖓' ;; *雨*) printf '󰖗' ;; *雪*) printf '󰼶' ;; *雾*|*霾*|*尘*|*沙*) printf '󰖑' ;;
        *) printf '󰔏' ;;
      esac
      ;;
  esac
}

fetch_astronomy_data() {
  local city="$1" lat="$2" lon="$3" today; today="$(date +%Y-%m-%d)"
  local cache="{}"; [[ -s "$DAILY_CACHE_FILE" ]] && cache="$(<"$DAILY_CACHE_FILE")"

  if [[ "$(jq -r --arg c "$city" '.[$c].date // empty' <<<"$cache" 2>/dev/null)" == "$today" ]]; then
    jq -c --arg c "$city" '.[$c]' <<<"$cache"
    return 0
  fi

  local resp
  resp="$(curl -fsS --compressed --connect-timeout 6 --max-time 12 \
    -H "X-QW-Api-Key: $QWEATHER_KEY" \
    "https://${QWEATHER_HOST}/v7/weather/3d?location=${lon},${lat}" 2>/dev/null || true)"
  [[ -z "$resp" ]] && { jq -c --arg c "$city" '.[$c] // {}' <<<"$cache"; return 0; }

  local parsed
  parsed="$(jq -c --arg date "$today" '{
    date: $date, sunrise: (.daily[0].sunrise // "--"), sunset: (.daily[0].sunset // "--"),
    moonPhase: (.daily[0].moonPhase // "--"), tempMax: (.daily[0].tempMax // "--"), tempMin: (.daily[0].tempMin // "--")
  }' <<<"$resp" 2>/dev/null || echo "{}")"

  if [[ -n "$parsed" && "$parsed" != "{}" ]]; then
    cache="$(jq --arg c "$city" --argjson d "$parsed" '. + {($c): $d}' <<<"$cache")"
    local tmp="${DAILY_CACHE_FILE}.${BASHPID:-$$}"
    printf '%s\n' "$cache" > "$tmp" && mv "$tmp" "$DAILY_CACHE_FILE"
  fi
  printf '%s\n' "$parsed"
}

fetch_hourly_pop() {
  local city="$1" lat="$2" lon="$3" now; now="$(date +%s)"
  local cache="{}"; [[ -s "$HOURLY_CACHE_FILE" ]] && cache="$(<"$HOURLY_CACHE_FILE")"

  local mtime; mtime="$(jq -r --arg c "$city" '.[$c].updated_at // 0' <<<"$cache" 2>/dev/null || echo 0)"
  if ((now - mtime < 1800)); then
    jq -r --arg c "$city" '.[$c].pop // "--"' <<<"$cache" 2>/dev/null || echo "--"
    return 0
  fi

  local resp pop
  resp="$(curl -fsS --compressed --connect-timeout 4 --max-time 8 \
    -H "X-QW-Api-Key: $QWEATHER_KEY" \
    "https://${QWEATHER_HOST}/v7/weather/24h?location=${lon},${lat}" 2>/dev/null || true)"
  pop="$(jq -r '.hourly[0].pop // "--"' <<<"$resp" 2>/dev/null || echo "--")"
  [[ "$pop" != "--" && -n "$pop" && "$pop" != "null" ]] && pop="${pop}%" || pop="0%"

  cache="$(jq --arg c "$city" --arg p "$pop" --argjson t "$now" '. + {($c): {pop: $p, updated_at: $t}}' <<<"$cache" 2>/dev/null || echo "{}")"
  local tmp="${HOURLY_CACHE_FILE}.${BASHPID:-$$}"
  printf '%s\n' "$cache" > "$tmp" && mv "$tmp" "$HOURLY_CACHE_FILE"
  printf '%s\n' "$pop"
}

fetch_all_weather() {
  load_config
  [[ -n "$QWEATHER_KEY" ]] || return 1

  local -a cities=()
  mapfile -t cities < <(jq -r '.locations | keys[]' "$CONFIG_FILE" 2>/dev/null)
  [[ ${#cities[@]} -gt 0 ]] || return 0

  local results_obj="{}" local_time; local_time="$(date +%H:%M:%S)"

  for city in "${cities[@]}"; do
    local coords; coords="$(jq -r --arg c "$city" '.locations[$c] // empty' "$CONFIG_FILE" 2>/dev/null)"
    [[ -n "$coords" ]] || continue
    local lat="${coords%%,*}" lon="${coords##*,}"

    local resp
    resp="$(curl -fsS --compressed --connect-timeout 8 --max-time 15 \
      -H "X-QW-Api-Key: $QWEATHER_KEY" \
      "https://${QWEATHER_HOST}/weather/v1/current/${lat}/${lon}" 2>/dev/null || true)"
    [[ -n "$resp" ]] || continue

    local minutely_resp rain_summary=""
    minutely_resp="$(curl -fsS --compressed --connect-timeout 4 --max-time 8 \
      -H "X-QW-Api-Key: $QWEATHER_KEY" \
      "https://${QWEATHER_HOST}/v7/minutely/5m?location=${lon},${lat}" 2>/dev/null || true)"
    [[ -n "$minutely_resp" ]] && rain_summary="$(jq -r '.summary // ""' <<<"$minutely_resp" 2>/dev/null || true)"

    local astro pop
    astro="$(fetch_astronomy_data "$city" "$lat" "$lon")"
    pop="$(fetch_hourly_pop "$city" "$lat" "$lon")"

    local parsed
    parsed="$(jq -c --arg update_time "$local_time" --arg rain_summary "$rain_summary" --arg pop "$pop" --argjson astro "$astro" '{
      condition: (.condition.text // "未知"),
      code: (.condition.code // ""),
      temp: (((.temperature.value // 0) | round | tostring) + "°C"),
      feelsLike: (((.feelsLike.value // 0) * 10 | round / 10 | tostring) + "°C"),
      humidity: (((.humidity // 0) * 100 | round | tostring) + "%"),
      pop: $pop,
      wind_compass: (.wind.direction.compass // ""),
      wind_deg: ((.wind.direction.degree // "") | tostring),
      wind_scale: ((.wind.scale // "") | tostring),
      wind_speed: (((.wind.speed.value // 0) * 10 | round / 10 | tostring) + " m/s"),
      precip: (((.precipitation.amount.value // 0) * 10 | round / 10 | tostring) + " mm"),
      precip_raw: (.precipitation.amount.value // 0),
      rain_summary: $rain_summary,
      cloud: (if .cloudCover then (((.cloudCover * 100 | round) | tostring) + "%") else "--" end),
      uvIndex: ((.uvIndex // 0) | tostring),
      sunrise: ($astro.sunrise // "--"),
      sunset: ($astro.sunset // "--"),
      moonPhase: ($astro.moonPhase // "--"),
      tempMax: ($astro.tempMax // "--"),
      tempMin: ($astro.tempMin // "--"),
      update_time: $update_time
    }' <<<"$resp" 2>/dev/null || true)"

    [[ -n "$parsed" ]] && results_obj="$(jq -c --arg c "$city" --argjson d "$parsed" '. + {($c): $d}' <<<"$results_obj")"
  done

  if (( $(jq 'keys | length' <<<"$results_obj") > 0 )); then
    local now; now="$(date +%s)"
    local tmp="${WEATHER_CACHE_FILE}.${BASHPID:-$$}"
    jq -n --argjson now "$now" --argjson cities "$results_obj" '{updated_at: $now, cities: $cities}' > "$tmp" && mv "$tmp" "$WEATHER_CACHE_FILE"
  fi
}

cache_is_fresh() {
  [[ -s "$WEATHER_CACHE_FILE" ]] || return 1
  local mtime now; mtime="$(jq -r '.updated_at // 0' "$WEATHER_CACHE_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  ((now - mtime < 300))
}

refresh_cache_async() {
  (
    local lock_fd
    exec {lock_fd}>"$LOCK_FILE" || exit 0
    flock -n "$lock_fd" || exit 0
    fetch_all_weather || true
    command -v tmux >/dev/null 2>&1 && tmux refresh-client -S 2>/dev/null || true
  ) >/dev/null 2>&1 &
}

get_current_weather() {
  load_config
  local data; data="$(jq -c --arg c "$CURRENT_CITY" '.cities[$c] // (.cities | to_entries[0].value) // {}' "$WEATHER_CACHE_FILE" 2>/dev/null || echo "{}")"
  local cond code temp
  cond="$(jq -r '.condition // "晴"' <<<"$data")"
  code="$(jq -r '.code // "100"' <<<"$data")"
  temp="$(jq -r '.temp // "--"' <<<"$data")"
  printf '%s\t%s\t%s\t%s\n' "$(weather_icon "$code" "$cond")" "$temp" "$cond" "$CURRENT_CITY"
}

render_module() {
  cache_is_fresh || refresh_cache_async
  local icon temp _ _
  IFS=$'\t' read -r icon temp _ _ < <(get_current_weather)
  printf '#[range=user|weather]%s %s#[norange]' "$icon" "$temp"
}

render_plain() {
  local icon temp cond city
  IFS=$'\t' read -r icon temp cond city < <(get_current_weather)
  printf '%s %s: %s %s\n' "$icon" "$city" "$cond" "$temp"
}

select_city() {
  local city="${1:-}"; [[ -n "$city" ]] || return 0
  ensure_config
  local tmp="${CONFIG_FILE}.${BASHPID:-$$}"
  jq --arg c "$city" '.current = $c' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  command -v tmux >/dev/null 2>&1 && tmux refresh-client -S 2>/dev/null || true
}

refresh_now() {
  fetch_all_weather
  if command -v tmux >/dev/null 2>&1; then
    tmux refresh-client -S 2>/dev/null || true
    tmux display-message "和风天气: 数据已更新" 2>/dev/null || true
  fi
}

pad_detail() {
  local icon="$1" label="$2" val="$3"
  local pad_len=$(( (4 - ${#label}) * 2 + 2 )) pad=""
  (( pad_len > 0 )) && printf -v pad '%*s' "$pad_len" ""
  printf '%s %s%s%s' "$icon" "$label" "$pad" "$val"
}

show_menu() {
  local client="${1:-}" mouse_x="${2:-}"
  load_config
  [[ -s "$WEATHER_CACHE_FILE" ]] || fetch_all_weather

  local -a menu_args=("-M")
  [[ -n "$client" ]] && menu_args+=("-c" "$client")
  [[ -n "$mouse_x" && "$mouse_x" =~ ^[0-9]+$ ]] && menu_args+=("-x" "$mouse_x" "-y" "S") || menu_args+=("-x" "M" "-y" "S")

  local -a city_lines=()
  mapfile -t city_lines < <(jq -r --slurpfile cfg "$CONFIG_FILE" '
    ($cfg[0].locations | keys[]) as $c
    | [$c, (.cities[$c].condition // "--"), (.cities[$c].code // ""), (.cities[$c].temp // "--")]
    | @tsv
  ' "$WEATHER_CACHE_FILE" 2>/dev/null)

  local max_len=2
  for line in "${city_lines[@]}"; do
    local c="${line%%$'\t'*}"
    (( ${#c} > max_len )) && max_len=${#c}
  done

  local idx=1
  for line in "${city_lines[@]}"; do
    local city cond code temp
    IFS=$'\t' read -r city cond code temp <<<"$line"
    local icon; icon="$(weather_icon "$code" "$cond")"
    local c_pad="" cd_pad=""
    (( (max_len - ${#city}) * 2 > 0 )) && printf -v c_pad '%*s' "$(( (max_len - ${#city}) * 2 ))" ""
    (( (2 - ${#cond}) * 2 > 0 )) && printf -v cd_pad '%*s' "$(( (2 - ${#cond}) * 2 ))" ""

    local label
    if [[ "$city" == "$CURRENT_CITY" ]]; then
      label=" ${city}${c_pad}  ${icon} ${cond}${cd_pad}  ${temp}"
    else
      label="#[dim]  ${city}${c_pad}  ${icon} ${cond}${cd_pad}  ${temp}#[nodim]"
    fi
    menu_args+=("$label" "$idx" "run-shell -b '${SCRIPT_PATH} select \"${city}\"'")
    ((idx++))
  done

  menu_args+=("")

  local cur_data; cur_data="$(jq -c --arg c "$CURRENT_CITY" '.cities[$c] // {}' "$WEATHER_CACHE_FILE" 2>/dev/null || echo "{}")"
  if [[ -n "$cur_data" && "$cur_data" != "{}" ]]; then
    local cur_feels cur_hum cur_pop cur_w_comp cur_w_deg cur_w_scale cur_w_spd cur_precip cur_precip_raw cur_rain_summary cur_cloud cur_uv cur_sunrise cur_sunset cur_moon cur_max cur_min cur_time
    IFS=$'\t' read -r cur_feels cur_hum cur_pop cur_w_comp cur_w_deg cur_w_scale cur_w_spd cur_precip cur_precip_raw cur_rain_summary cur_cloud cur_uv cur_sunrise cur_sunset cur_moon cur_max cur_min cur_time < <(
      jq -r '[.feelsLike // "--", .humidity // "--", .pop // "--", .wind_compass // "", .wind_deg // "", .wind_scale // "", .wind_speed // "", .precip // "--", .precip_raw // 0, .rain_summary // "", .cloud // "--", .uvIndex // "--", .sunrise // "--", .sunset // "--", .moonPhase // "--", .tempMax // "--", .tempMin // "--", .update_time // "--:--"] | @tsv' <<<"$cur_data"
    )

    local wind_text="${COMPASS[${cur_w_comp,,}]:-$cur_w_comp}"
    [[ -n "$cur_w_deg" ]] && wind_text+=" ${cur_w_deg}°"
    local wind_spd=""
    [[ -n "$cur_w_scale" ]] && wind_spd+="${cur_w_scale}级 "
    [[ -n "$cur_w_spd" ]] && wind_spd+="${cur_w_spd}"

    [[ "$cur_min" != "--" && "$cur_max" != "--" ]] && menu_args+=("$(pad_detail "󰈸" "全天气温" "${cur_min}°C ~ ${cur_max}°C")" "" "")
    menu_args+=("$(pad_detail "󰔄" "体感" "$cur_feels")" "" "")
    menu_args+=("$(pad_detail "󰖝" "湿度" "$cur_hum")" "" "")
    [[ "$cur_pop" != "--" && -n "$cur_pop" ]] && menu_args+=("$(pad_detail "󰖗" "降雨概率" "$cur_pop")" "" "")
    menu_args+=("$(pad_detail "󰆣" "风向" "$wind_text")" "" "")
    menu_args+=("$(pad_detail "󰖞" "风速" "$wind_spd")" "" "")
    [[ -n "$cur_cloud" && "$cur_cloud" != "--" ]] && menu_args+=("$(pad_detail "󰖐" "云量" "$cur_cloud")" "" "")
    menu_args+=("$(pad_detail "󰖙" "紫外线" "$cur_uv")" "" "")
    [[ "$cur_sunrise" != "--" && "$cur_sunset" != "--" ]] && menu_args+=("$(pad_detail "󰖜" "日出日落" "${cur_sunrise} / ${cur_sunset}")" "" "")
    [[ "$cur_moon" != "--" ]] && menu_args+=("$(pad_detail "${MOON[$cur_moon]:-󰽢}" "月相" "$cur_moon")" "" "")

    if awk "BEGIN {exit !($cur_precip_raw > 0)}" 2>/dev/null || { [[ "$cur_rain_summary" =~ (雨|雪) ]] && ! [[ "$cur_rain_summary" =~ 无(降水|雨|降雪) ]]; }; then
      awk "BEGIN {exit !($cur_precip_raw > 0)}" 2>/dev/null && menu_args+=("$(pad_detail "󰖖" "降雨量" "$cur_precip")" "" "")
      [[ -n "$cur_rain_summary" ]] && menu_args+=("$(pad_detail "󰖗" "降水预报" "$cur_rain_summary")" "" "")
    fi
  else
    menu_args+=("暂无 ${CURRENT_CITY} 详细数据" "" "")
  fi

  menu_args+=("" "󰑐 刷新 (${cur_time:-"--:--"})" "r" "run-shell -b '${SCRIPT_PATH} refresh'")

  if command -v tmux >/dev/null 2>&1; then
    tmux display-menu "${menu_args[@]}"
  else
    printf 'Menu items count: %d\n' "${#menu_args[@]}"
  fi
}

main() {
  case "${1:-module}" in
    module)  render_module ;;
    plain)   render_plain ;;
    select)  select_city "${2:-}" ;;
    refresh) refresh_now ;;
    menu)    show_menu "${2:-}" "${3:-}" ;;
    fetch)   fetch_all_weather ;;
    *)       render_module ;;
  esac
}

main "$@"
