#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_RED_RAILS_MASTER_KEY:?PROJECT_RED_RAILS_MASTER_KEY is required}"
: "${PROJECT_RED_MEDIA_BUCKET:?PROJECT_RED_MEDIA_BUCKET is required}"
: "${PROJECT_RED_MEDIA_CDN_URL:?PROJECT_RED_MEDIA_CDN_URL is required}"

if ! command -v redis-server >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server
fi

if grep -q '^maxmemory ' /etc/redis/redis.conf; then
  sed -i 's/^maxmemory .*/maxmemory 128mb/' /etc/redis/redis.conf
else
  printf '\nmaxmemory 128mb\n' >> /etc/redis/redis.conf
fi

if grep -q '^maxmemory-policy ' /etc/redis/redis.conf; then
  sed -i 's/^maxmemory-policy .*/maxmemory-policy noeviction/' /etc/redis/redis.conf
else
  printf 'maxmemory-policy noeviction\n' >> /etc/redis/redis.conf
fi

systemctl enable redis-server
systemctl restart redis-server
redis-cli ping

install -d -m 0750 /etc/project-red-crm

# The Picaivid master database connection remains on the host. It is used only
# to create the isolated CRM role and database; its credential is not copied.
set -a
# shellcheck disable=SC1091
source /etc/picaivid/rails.env
set +a

project_red_db_password="$(openssl rand -hex 32)"

if ! psql "$DATABASE_URL" -tAc "SELECT 1 FROM pg_roles WHERE rolname = \$\$project_red_crm\$\$" | grep -q 1; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -c "CREATE ROLE project_red_crm LOGIN PASSWORD \$\$${project_red_db_password}\$\$"
else
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -c "ALTER ROLE project_red_crm LOGIN PASSWORD \$\$${project_red_db_password}\$\$"
fi

if ! psql "$DATABASE_URL" -tAc "SELECT 1 FROM pg_database WHERE datname = \$\$project_red_crm\$\$" | grep -q 1; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE project_red_crm"
fi

project_red_db_host="$(printf '%s\n' "$DATABASE_URL" | sed -E 's#^[[:alpha:]][[:alnum:]+.-]*://([^@/]+@)?([^/?]+).*#\2#')"
project_red_admin_database_url="$(printf '%s\n' "$DATABASE_URL" | sed -E 's#/[[:alnum:]_-]+(\?.*)?$#/project_red_crm\1#')"
project_red_database_url="postgresql://project_red_crm:${project_red_db_password}@${project_red_db_host}/project_red_crm?sslmode=require"

# RDS database administrators cannot SET ROLE to a newly-created role. Keep
# the database owned by the existing administrator and give the CRM role all
# required database and public-schema privileges instead.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -c "GRANT ALL PRIVILEGES ON DATABASE project_red_crm TO project_red_crm"
psql "$project_red_admin_database_url" -v ON_ERROR_STOP=1 \
  -c "GRANT ALL ON SCHEMA public TO project_red_crm"

{
  printf '%s\n' \
    'RAILS_ENV=production' \
    'RAILS_LOG_LEVEL=info' \
    'PORT=3003' \
    'RAILS_MAX_THREADS=3' \
    "DATABASE_URL=${project_red_database_url}" \
    'REDIS_URL=redis://127.0.0.1:6379/0' \
    'AWS_REGION=us-west-2' \
    "PROJECT_RED_MEDIA_BUCKET=${PROJECT_RED_MEDIA_BUCKET}" \
    "PROJECT_RED_MEDIA_CDN_URL=${PROJECT_RED_MEDIA_CDN_URL}" \
    'CRM_UI_ORIGIN=https://crm.projectred.ca' \
    'PUBLIC_SITE_ORIGIN=https://projectred.ca' \
    'PORTAL_URL=https://crm.projectred.ca' \
    'MAILER_HOST=api.projectred.ca' \
    'MAILER_PROTOCOL=https' \
    'MAILER_FROM=ProjectRed <no-reply@projectred.ca>' \
    'AUTH_MAILER_FROM=ProjectRed <no-reply@projectred.ca>' \
    "RAILS_MASTER_KEY=${PROJECT_RED_RAILS_MASTER_KEY}"
} > /etc/project-red-crm/api.env
chmod 600 /etc/project-red-crm/api.env

{
  printf '%s\n' \
    'NODE_ENV=production' \
    'PORT=3004' \
    'NEXT_PUBLIC_CRM_API_URL=https://api.projectred.ca/api/v1'
} > /etc/project-red-crm/ui.env
chmod 640 /etc/project-red-crm/ui.env

printf '%s\n' \
  'server {' \
  '  listen 80;' \
  '  server_name api.projectred.ca;' \
  '  client_max_body_size 500m;' \
  '  location / {' \
  '    proxy_pass http://127.0.0.1:3003;' \
  '    proxy_http_version 1.1;' \
  '    proxy_set_header Host $host;' \
  '    proxy_set_header X-Real-IP $remote_addr;' \
  '    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
  '    proxy_set_header X-Forwarded-Proto $scheme;' \
  '  }' \
  '}' \
  '' \
  'server {' \
  '  listen 80;' \
  '  server_name crm.projectred.ca;' \
  '  location / {' \
  '    proxy_pass http://127.0.0.1:3004;' \
  '    proxy_http_version 1.1;' \
  '    proxy_set_header Host $host;' \
  '    proxy_set_header X-Real-IP $remote_addr;' \
  '    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
  '    proxy_set_header X-Forwarded-Proto $scheme;' \
  '  }' \
  '}' > /etc/nginx/conf.d/project-red-crm.conf

nginx -t
systemctl reload nginx

printf '%s\n' 'Project Red CRM bootstrap complete'
