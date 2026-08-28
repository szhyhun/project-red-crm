#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="${RELEASE_DIR:-/srv/project-red-crm-api.next}"
CURRENT_DIR="${CURRENT_DIR:-/srv/project-red-crm-api}"
PREVIOUS_DIR="${PREVIOUS_DIR:-/srv/project-red-crm-api.prev}"
ENV_FILE="${ENV_FILE:-/etc/project-red-crm/api.env}"
APP_USER="${APP_USER:-ubuntu}"
API_SERVICE="${API_SERVICE:-project-red-crm-api}"
WORKER_SERVICE="${WORKER_SERVICE:-project-red-crm-worker}"
APP_PORT="${PORT:-3003}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing production environment file: ${ENV_FILE}" >&2
  exit 1
fi

if [[ ! -f "${RELEASE_DIR}/Gemfile" ]]; then
  echo "Release directory does not contain a Gemfile: ${RELEASE_DIR}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

export PATH="/home/ubuntu/.rbenv/bin:/home/ubuntu/.rbenv/shims:${PATH}"
eval "$(rbenv init - bash)"

echo "[deploy] verifying Ruby runtime"
ruby --version

echo "[deploy] installing API dependencies"
cd "${RELEASE_DIR}"
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'
bundle install

echo "[deploy] running database migrations"
RAILS_ENV=production bundle exec rails db:migrate

echo "[deploy] activating release"
systemctl stop "${WORKER_SERVICE}" || true
systemctl stop "${API_SERVICE}" || true
rm -rf "${PREVIOUS_DIR}"

if [[ -d "${CURRENT_DIR}" ]]; then
  mv "${CURRENT_DIR}" "${PREVIOUS_DIR}"
fi

mv "${RELEASE_DIR}" "${CURRENT_DIR}"
chown -R "${APP_USER}:${APP_USER}" "${CURRENT_DIR}"

install -m 0644 "${CURRENT_DIR}/deploy/systemd/${API_SERVICE}.service" "/etc/systemd/system/${API_SERVICE}.service"
install -m 0644 "${CURRENT_DIR}/deploy/systemd/${WORKER_SERVICE}.service" "/etc/systemd/system/${WORKER_SERVICE}.service"
systemctl daemon-reload

rollback() {
  echo "[deploy] release failed; restoring the previous API release" >&2
  systemctl stop "${WORKER_SERVICE}" || true
  systemctl stop "${API_SERVICE}" || true
  rm -rf "${CURRENT_DIR}"

  if [[ -d "${PREVIOUS_DIR}" ]]; then
    mv "${PREVIOUS_DIR}" "${CURRENT_DIR}"
    systemctl restart "${API_SERVICE}"
    systemctl restart "${WORKER_SERVICE}"
  fi
}

if ! systemctl restart "${API_SERVICE}" || ! systemctl restart "${WORKER_SERVICE}"; then
  rollback
  exit 1
fi

if ! systemctl is-active --quiet "${API_SERVICE}" || ! systemctl is-active --quiet "${WORKER_SERVICE}"; then
  rollback
  exit 1
fi

api_healthy=false
for attempt in $(seq 1 20); do
  if curl --fail --silent --show-error --max-time 15 \
    -H 'Host: api.projectred.ca' \
    "http://127.0.0.1:${APP_PORT}/up" >/dev/null; then
    api_healthy=true
    break
  fi

  sleep 3
done

if [[ "${api_healthy}" != true ]]; then
  rollback
  exit 1
fi

echo "[deploy] API release is active"
