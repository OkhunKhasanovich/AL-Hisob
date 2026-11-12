#!/usr/bin/env bash
# Первичная настройка VPS (Ubuntu/Debian). Запускать от root ОДИН раз:
#
#   DOMAIN=api.example.com EMAIL=you@example.com bash bootstrap.sh
#
# Что делает: ставит Docker, nginx, certbot; создаёт пользователя deploy; клонирует репозиторий в
# /opt/al-hisob; создаёт deploy/.env со случайными секретами; настраивает nginx и HTTPS;
# запускает сервер. Повторный запуск безопасен: существующий .env не перезаписывается.
set -euo pipefail

: "${DOMAIN:?Укажите DOMAIN, например DOMAIN=api.example.com}"
: "${EMAIL:?Укажите EMAIL для уведомлений от центра сертификации}"
REPO_URL="${REPO_URL:-https://github.com/OkhunKhasanovich/Al-Hisob.git}"
APP_DIR="${APP_DIR:-/opt/al-hisob}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root (sudo -i)." >&2
  exit 1
fi

echo "==> Пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git ufw nginx certbot python3-certbot-nginx openssl
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y docker.io
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-v2 || apt-get install -y docker-compose-plugin
fi
systemctl enable --now docker

echo "==> Пользователь $DEPLOY_USER"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"

echo "==> Код в $APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"
git config --global --add safe.directory "$APP_DIR" || true

ENV_FILE="$APP_DIR/deploy/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "==> Создаю $ENV_FILE со случайными секретами"
  umask 077
  cat > "$ENV_FILE" <<ENVEOF
POSTGRES_PASSWORD=$(openssl rand -hex 24)
PUBLIC_BASE_URL=https://$DOMAIN
JWT_SECRET=$(openssl rand -hex 32)
TELEGRAM_BOT_TOKEN=
TELEGRAM_BOT_USERNAME=
TELEGRAM_WEBHOOK_SECRET=$(openssl rand -hex 24)
ENVEOF
  chown "$DEPLOY_USER:$DEPLOY_USER" "$ENV_FILE"
fi

echo "==> nginx"
SITE="/etc/nginx/sites-available/al-hisob"
sed "s/__DOMAIN__/$DOMAIN/g" "$APP_DIR/deploy/nginx/al-hisob.conf.template" > "$SITE"
ln -sf "$SITE" /etc/nginx/sites-enabled/al-hisob
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Файрвол (SSH, HTTP, HTTPS)"
ufw allow OpenSSH >/dev/null
ufw allow 'Nginx Full' >/dev/null
ufw --force enable >/dev/null

echo "==> HTTPS-сертификат для $DOMAIN"
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --no-eff-email --non-interactive --redirect

if ! grep -Eq '^TELEGRAM_BOT_TOKEN=.+' "$ENV_FILE" || ! grep -Eq '^TELEGRAM_BOT_USERNAME=.+' "$ENV_FILE"; then
  cat <<MSG

Почти готово. Осталось вписать данные Telegram-бота для входа в файл:
  $ENV_FILE
(строки TELEGRAM_BOT_TOKEN= и TELEGRAM_BOT_USERNAME=), затем выполнить:
  cd $APP_DIR/deploy && docker compose up -d --build
  docker compose exec -T api python -m app.cli set-webhook
MSG
  exit 0
fi

echo "==> Запуск сервера"
cd "$APP_DIR/deploy"
docker compose up -d --build
docker compose exec -T api python -m app.cli set-webhook
echo "Готово: https://$DOMAIN/health"
