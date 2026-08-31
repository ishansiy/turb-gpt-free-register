#!/usr/bin/env bash
set -eo pipefail

echo "=================================================="
echo "🚀 启动 Turb GPT Free Register (ModelScope Studio)"
echo "=================================================="

# 0. 持久化目录软链与恢复 (/mnt/workspace)
# ModelScope 创空间持久盘挂载在 /mnt/workspace
PERSIST_DIR="/mnt/workspace/turb-gpt-data"
if [ -d "/mnt/workspace" ]; then
    echo "[0/3] 初始化 /mnt/workspace 持久化数据目录..."
    mkdir -p "${PERSIST_DIR}"
    mkdir -p "${PERSIST_DIR}/注册日志"
    mkdir -p "${PERSIST_DIR}/codex_accounts"
    mkdir -p "${PERSIST_DIR}/codex_agent_accounts"

    # 1) 持久化 .env（配置项）
    if [ -f "${PERSIST_DIR}/.env" ]; then
        echo "  - 从持久目录恢复 .env 配置"
        cp -f "${PERSIST_DIR}/.env" /app/.env
    elif [ -f "/app/.env" ]; then
        echo "  - 备份初始 /app/.env 到持久目录"
        cp -f /app/.env "${PERSIST_DIR}/.env"
    fi
    # 建立软链，后续 WebUI 改写 .env 直接落盘持久目录
    ln -sf "${PERSIST_DIR}/.env" /app/.env

    # 2) 持久化 turb.sqlite3（账号池、邮箱池、任务历史）
    if [ -f "${PERSIST_DIR}/turb.sqlite3" ]; then
        echo "  - 挂载持久化 SQLite 数据库 turb.sqlite3"
    elif [ -f "/app/turb.sqlite3" ]; then
        echo "  - 迁移初始 turb.sqlite3 到持久目录"
        cp -f /app/turb.sqlite3 "${PERSIST_DIR}/turb.sqlite3"
    fi
    ln -sf "${PERSIST_DIR}/turb.sqlite3" /app/turb.sqlite3

    # 3) 持久化日志与导出的凭证目录
    rm -rf /app/注册日志 /app/codex_accounts /app/codex_agent_accounts
    ln -sf "${PERSIST_DIR}/注册日志" /app/注册日志
    ln -sf "${PERSIST_DIR}/codex_accounts" /app/codex_accounts
    ln -sf "${PERSIST_DIR}/codex_agent_accounts" /app/codex_agent_accounts
    echo "✓ 持久化链接初始化完成"
else
    echo "[0/3] 未检测到 /mnt/workspace，使用容器本地存储"
fi

# 1. 启动 Xvfb 虚拟显示服务器（供有头浏览器/指纹环境使用）
DISPLAY_NUM=99
echo "[1/3] 检查并启动 Xvfb 虚拟屏幕 :${DISPLAY_NUM} (1920x1080)..."
if ! pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; then
    Xvfb :${DISPLAY_NUM} -screen 0 1920x1080x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
    sleep 1
    echo "✓ Xvfb 启动成功 (DISPLAY=:${DISPLAY_NUM})"
else
    echo "✓ Xvfb 已在运行"
fi
export DISPLAY=:${DISPLAY_NUM}

# 2. 环境配置
PORT="${PORT:-7860}"
HOST="${HOST:-0.0.0.0}"
echo "[2/3] 配置服务端口: ${HOST}:${PORT}"

# 3. 启动 WebUI
echo "[3/3] 启动 WebUI 服务..."
exec python web.py --host "${HOST}" --port "${PORT}"
