#!/usr/bin/env bash
# ==========================================================
#  日常启动: 数据库 + 判题机 + Django 后端
#  用法:  cd ~/qduoj/OnlineJudge && bash start_backend.sh
# ==========================================================
set -e

TOKEN="${TOKEN:-my_dev_token_123}"
PORT="${PORT:-8000}"

cd "$(dirname "$0")"

echo "==> [1/4] 拉起 dockerd"
docker info >/dev/null 2>&1 || { sudo service docker start >/dev/null 2>&1 || true; sleep 5; }

echo "==> [2/4] 启动 PostgreSQL + Redis"
sudo docker compose -f redis-postgres.yml -p ojdb start 2>/dev/null \
  || sudo docker-compose -f redis-postgres.yml -p ojdb up -d
until sudo docker exec oj-postgres pg_isready -U onlinejudge >/dev/null 2>&1; do sleep 2; done
echo "     数据库就绪"

echo "==> [3/4] 启动判题机"
if [ -f judge-server.yml ]; then
  sudo docker compose -f judge-server.yml -p judge-server start 2>/dev/null \
    || sudo docker-compose -f judge-server.yml -p judge-server up -d
  echo "     判题机就绪 (12358)"
fi

echo "==> [4/4] 启动 Django (0.0.0.0:${PORT})"
source .venv/bin/activate 2>/dev/null || true
export JUDGE_SERVER_TOKEN="$TOKEN"
exec python manage.py runserver 0.0.0.0:"$PORT" --noreload
