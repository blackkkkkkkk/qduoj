#!/usr/bin/env bash
# ==========================================================
#  QDUOJ 后端开发环境 —— 一次性搭建 (WSL2 / Ubuntu)
#  用法:  cd ~/qduoj && bash setup_backend.sh
# ==========================================================
set -e

TOKEN="${TOKEN:-my_dev_token_123}"
PYVER="3.8.10"
INSTALL_DIR="${INSTALL_DIR:-$HOME/qduoj}"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
log() { echo -e "${GRN}==>${NC} $1"; }
warn() { echo -e "${YEL}[warn]${NC} $1"; }

# ---------------------------------------------------------
log "[0/7] 安装系统依赖"
# ---------------------------------------------------------
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git curl vim build-essential \
  python3-dev libpq-dev libssl-dev libffi-dev \
  pkg-config gcc make
# psycopg2 源码编译需要 libpq-dev + python3-dev; 少了必然报 pg_config not found

# ---------------------------------------------------------
log "[1/7] 准备 Python ${PYVER}"
# ---------------------------------------------------------
if ! command -v pyenv >/dev/null 2>&1; then
  warn "未检测到 pyenv, 正在安装 (qduoj 在 3.8 下最稳, 3.10+ 依赖容易炸)"
  curl -sS https://pyenv.run | bash
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
  cat >> ~/.bashrc <<'EOF'
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
else
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

pyenv install -s "$PYVER"
pyenv local "$PYVER"
python -V

# ---------------------------------------------------------
log "[2/7] 拉取后端源码"
# ---------------------------------------------------------
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
if [ ! -d OnlineJudge ]; then
  # 二次开发建议先 fork 再 clone 自己的仓库
  git clone https://github.com/QingdaoU/OnlineJudge.git
fi
cd OnlineJudge

# ---------------------------------------------------------
log "[3/7] 安装 Python 依赖"
# ---------------------------------------------------------
python -m venv .venv 2>/dev/null || true
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -q --upgrade pip setuptools wheel
# 国内源 + 不预编译 psycopg2(镜像里的二进制常与系统 libpq 不匹配)
pip install -r deploy/requirements.txt \
  -i https://mirrors.aliyun.com/pypi/simple/ \
  --no-binary psycopg2

# ---------------------------------------------------------
log "[4/7] 写入 custom_settings.py"
# ---------------------------------------------------------
cat > custom_settings.py <<EOF
# -*- coding: utf-8 -*-
SECRET_KEY = "dev-only-secret-key"
DEBUG = True
ALLOWED_HOSTS = ["*"]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql_psycopg2",
        "HOST": "127.0.0.1",
        "PORT": 5435,
        "NAME": "onlinejudge",
        "USER": "onlinejudge",
        "PASSWORD": "onlinejudge",
    }
}

REDIS_CONF = {"host": "127.0.0.1", "port": 6380}

JUDGE_SERVER_TOKEN = "${TOKEN}"

LANGUAGE_CODE = "zh-hans"
TIME_ZONE = "Asia/Shanghai"
USE_TZ = False

CORS_ORIGIN_ALLOW_ALL = True
CORS_ALLOW_CREDENTIALS = True
EOF
log "     已生成 custom_settings.py (TOKEN=${TOKEN})"

# ---------------------------------------------------------
log "[5/7] 启动 PostgreSQL + Redis"
# ---------------------------------------------------------
# WSL2 没有 systemd, 需要手动拉起 dockerd
if ! docker info >/dev/null 2>&1; then
  sudo service docker start || sudo dockerd >/dev/null 2>&1 &
  sleep 5
fi
cp -f ../qduoj-dev/redis-postgres.yml ./redis-postgres.yml 2>/dev/null || cat > redis-postgres.yml <<'EOF'
version: "3"
services:
  oj-redis:
    image: redis:6-alpine
    container_name: oj-redis
    restart: always
    volumes: ["./data_dev/redis:/data"]
    ports: ["0.0.0.0:6380:6379"]
  oj-postgres:
    image: postgres:13-alpine
    container_name: oj-postgres
    restart: always
    volumes: ["./data_dev/postgres:/var/lib/postgresql/data"]
    environment:
      - POSTGRES_DB=onlinejudge
      - POSTGRES_USER=onlinejudge
      - POSTGRES_PASSWORD=onlinejudge
    ports: ["0.0.0.0:5435:5432"]
EOF

sudo docker compose -f redis-postgres.yml -p ojdb up -d 2>/dev/null \
  || sudo docker-compose -f redis-postgres.yml -p ojdb up -d

log "     等待数据库就绪 ..."
sleep 12
until sudo docker exec oj-postgres pg_isready -U onlinejudge >/dev/null 2>&1; do
  sleep 2
done
log "     PostgreSQL 已就绪"

# ---------------------------------------------------------
log "[6/7] 初始化数据库"
# ---------------------------------------------------------
mkdir -p data/config data/test_case data/log
[ -f data/config/secret.key ] || \
  echo "$(head -c 64 /dev/urandom | base64 | tr -d '/+=' | head -c 32)" > data/config/secret.key

export JUDGE_SERVER_TOKEN="$TOKEN"
python manage.py migrate
python manage.py inituser --username root --password rootroot --action create_super_admin
log "     超级管理员: root / rootroot"

# ---------------------------------------------------------
log "[7/7] 启动判题机"
# ---------------------------------------------------------
cp -f ../qduoj-dev/judge-server.yml ./judge-server.yml 2>/dev/null || true
if [ -f judge-server.yml ]; then
  sed -i "s|TOKEN=.*|TOKEN=${TOKEN}|" judge-server.yml
  sudo docker compose -f judge-server.yml -p judge-server up -d 2>/dev/null \
    || sudo docker-compose -f judge-server.yml -p judge-server up -d
  log "     判题机已启动, 端口 12358"
fi

echo
echo -e "${GRN}==================== 完成 ====================${NC}"
echo "  后端目录   : $(pwd)"
echo "  TOKEN      : ${TOKEN}"
echo "  后端地址   : http://localhost:8000"
echo "  管理员     : root / rootroot"
echo "  判题机     : http://localhost:12358"
echo
echo "  下次启动只需:  cd $(pwd) && bash start_backend.sh"
echo -e "${GRN}=============================================${NC}"
