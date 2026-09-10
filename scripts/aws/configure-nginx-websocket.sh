#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${NGINX_WEBSOCKET_CONFIG:-/etc/nginx/conf.d/project-red-crm-temporary-sslip.conf}"
MAP_PATH="${NGINX_WEBSOCKET_MAP_CONFIG:-/etc/nginx/conf.d/project-red-crm-websocket-map.conf}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[nginx] proxy config not found; leaving the existing Nginx configuration unchanged: ${CONFIG_PATH}"
  exit 0
fi

temporary_config="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
temporary_map="$(mktemp "${MAP_PATH}.tmp.XXXXXX")"
cleanup() {
  rm -f "${temporary_config}" "${temporary_map}"
}
trap cleanup EXIT

map_changed=false
if ! grep -RqsF 'map $http_upgrade $connection_upgrade' /etc/nginx/conf.d; then
  printf '%s\n' \
    'map $http_upgrade $connection_upgrade {' \
    '  default upgrade;' \
    "  '' close;" \
    '}' > "${temporary_map}"

  if [[ ! -f "${MAP_PATH}" ]] || ! cmp -s "${temporary_map}" "${MAP_PATH}"; then
    install -m 0644 "${temporary_map}" "${MAP_PATH}"
    map_changed=true
  fi
fi

awk '
function emit_location(   line_number) {
  if (location_has_proxy && !location_has_upgrade) {
    for (line_number = 1; line_number <= line_count; line_number++) {
      if (line_number == line_count && lines[line_number] ~ /^[[:space:]]*}/) {
        print "    proxy_set_header Upgrade $http_upgrade;"
        print "    proxy_set_header Connection $connection_upgrade;"
      }
      print lines[line_number]
    }
  } else {
    for (line_number = 1; line_number <= line_count; line_number++) print lines[line_number]
  }

  delete lines
  line_count = 0
  location_has_proxy = 0
  location_has_upgrade = 0
}

{
  if (!in_location && $0 ~ /^[[:space:]]*location[[:space:]]+/) {
    in_location = 1
    line_count = 0
    location_has_proxy = 0
    location_has_upgrade = 0
  }

  if (in_location) {
    lines[++line_count] = $0
    if ($0 ~ /proxy_pass[[:space:]]/) location_has_proxy = 1
    if ($0 ~ /proxy_set_header[[:space:]]+Upgrade[[:space:]]/) location_has_upgrade = 1

    if ($0 ~ /^[[:space:]]*}/) {
      emit_location()
      in_location = 0
    }
  } else {
    print $0
  }
}

END {
  if (in_location) emit_location()
}
' "${CONFIG_PATH}" > "${temporary_config}"

config_changed=false
if ! cmp -s "${temporary_config}" "${CONFIG_PATH}"; then
  backup_path="${CONFIG_PATH}.pre-project-red-websocket"
  if [[ ! -e "${backup_path}" ]]; then
    install -m 0644 "${CONFIG_PATH}" "${backup_path}"
  fi
  install -m 0644 "${temporary_config}" "${CONFIG_PATH}"
  config_changed=true
fi

if [[ "${map_changed}" == true || "${config_changed}" == true ]]; then
  echo "[nginx] WebSocket proxy configuration updated"
else
  echo "[nginx] WebSocket proxy configuration already present"
fi

nginx -t
systemctl reload nginx
echo "[nginx] Nginx reloaded"
