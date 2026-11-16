#!/usr/bin/env bash
# ==========================================================
#  QDUOJ 后端依赖一键安装  (WSL2 / Ubuntu 22.04, Python 3.8.10)
#
#  用法:  cd ~/qduoj/OnlineJudge && bash install_deps.sh
#  快速通道(跳过 psycopg2 源码编译):
#         cd ~/qduoj/OnlineJudge && bash install_deps.sh --binary
# ==========================================================
set -e

GRN='\033[0;32m'; YEL='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GRN}==>${NC} $1"; }
warn() { echo -e "${YEL}[warn]${NC} $1"; }
err()  { echo -e "${RED}[error]${NC} $1"; }

FAST=0
[ "$1" = "--binary" ] && FAST=1

PY="${PY:-python3.8}"
INDEX="${INDEX:-https://mirrors.aliyun.com/pypi/simple/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ="$SCRIPT_DIR/requirements.txt"

# ---------------------------------------------------------
log "[1/6] 检查 Python 版本 (flake8 7.0.0 要求 >= 3.8.1)"
# ---------------------------------------------------------
command -v "$PY" >/dev/null 2>&1 || { err "找不到 $PY, 请先 pyenv install 3.8.10"; exit 1; }
"$PY" -V
"$PY" - <<'EOF'
import sys
if sys.version_info < (3, 8, 1):
    sys.exit("[error] Python 版本过低, flake8==7.0.0 需要 >= 3.8.1, 请用 3.8.10")
print("     Python 版本满足要求")
EOF

# ---------------------------------------------------------
log "[2/6] 安装系统编译依赖 (psycopg2 / pillow 必需)"
# ---------------------------------------------------------
sudo apt-get update -qq
sudo apt-get install -y -qq \
  build-essential \
  python3-dev \
  libpq-dev \
  libssl-dev \
  libffi-dev \
  zlib1g-dev \
  libjpeg-dev \
  pkg-config
# libpq-dev  → psycopg2 编译要 pg_config, 缺了必报 "pg_config executable not found"
# python3-dev → 提供 Python.h
# zlib/jpeg  → pillow 编译要
command -v pg_config >/dev/null 2>&1 && log "     pg_config: $(pg_config --version)" || warn "pg_config 仍不可用"

# ---------------------------------------------------------
log "[3/6] 创建虚拟环境"
# ---------------------------------------------------------
cd "$SCRIPT_DIR"
if [ ! -d .venv ]; then
  "$PY" -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -q --upgrade pip setuptools wheel -i "$INDEX"
python -V && pip -V

# ---------------------------------------------------------
log "[4/6] 安装依赖 (源: $INDEX)"
# ---------------------------------------------------------
if [ "$FAST" -eq 1 ]; then
  log "     快速通道: psycopg2 → psycopg2-binary (免编译)"
  sed 's/^psycopg2==/psycopg2-binary==/' "$REQ" > requirements.fast.txt
  pip install -r requirements.fast.txt -i "$INDEX"
else
  # 先装除 psycopg2 之外的全部(都有现成 wheel, 很快)
  log "     先装可免编译的包 ..."
  grep -v '^psycopg2==' "$REQ" > requirements.nopg.txt
  pip install -r requirements.nopg.txt -i "$INDEX"

  log "     单独处理 psycopg2 (Linux 无预编译 wheel, 需源码编译) ..."
  if pip install psycopg2==2.9.9 -i "$INDEX" 2>/tmp/pgerr.log; then
    log "     psycopg2 源码编译成功"
  else
    warn "psycopg2 源码编译失败, 自动降级为 psycopg2-binary"
    tail -5 /tmp/pgerr.log || true
    pip install psycopg2-binary==2.9.9 -i "$INDEX"
    warn "已安装 psycopg2-binary (开发环境完全可用; 生产环境建议改回 psycopg2)"
  fi
fi

# ---------------------------------------------------------
log "[5/6] 校验安装结果"
# ---------------------------------------------------------
python - <<'EOF'
import importlib, sys
checks = [
    ("django", "Django"), ("rest_framework", "DRF"),
    ("psycopg2", "psycopg2"), ("django_redis", "django-redis"),
    ("dramatiq", "dramatiq"), ("django_dramatiq", "django-dramatiq"),
    ("PIL", "pillow"), ("qrcode", "qrcode"), ("otpauth", "otpauth"),
    ("jsonfield", "jsonfield"), ("raven", "raven"), ("envelopes", "Envelopes"),
    ("xlsxwriter", "XlsxWriter"), ("gunicorn", "gunicorn"),
    ("cas", "django-cas-ng"), ("dateutil", "python-dateutil"),
]
bad = []
for mod, name in checks:
    try:
        importlib.import_module(mod)
        print(f"  OK   {name}")
    except Exception as e:
        print(f"  FAIL {name}: {e}")
        bad.append(name)

import django
print(f"\n  Django version: {django.get_version()}")
import psycopg2
print(f"  psycopg2 version: {psycopg2.__version__}")
sys.exit(1 if bad else 0)
EOF

# ---------------------------------------------------------
log "[6/6] 检查 flake8 插件是否注册成功"
# ---------------------------------------------------------
flake8 --version

echo
echo -e "${GRN}==================== 完成 ====================${NC}"
echo "  虚拟环境: $(pwd)/.venv"
echo "  激活方式: source .venv/bin/activate"
echo
echo "  下一步:"
echo "    export JUDGE_SERVER_TOKEN=my_dev_token_123"
echo "    python manage.py migrate"
echo "    python manage.py inituser --username root --password rootroot --action create_super_admin"
echo "    python manage.py runserver 0.0.0.0:8000"
echo -e "${GRN}=============================================${NC}"
