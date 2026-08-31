#!/usr/bin/env bash
set -eo pipefail

echo "=================================================="
echo "🚀 启动 Turb GPT Free Register (ModelScope Studio)"
echo "=================================================="

# 0. 持久化数据目录与安全恢复 (/mnt/workspace)
# ModelScope 创空间持久盘挂载在 /mnt/workspace (基于 OSSFS)
PERSIST_DIR="/mnt/workspace/turb-gpt-data"
if [ -d "/mnt/workspace" ]; then
    echo "[0/3] 初始化 /mnt/workspace 持久化数据目录..."
    mkdir -p "${PERSIST_DIR}" || true
    mkdir -p "${PERSIST_DIR}/注册日志" || true
    mkdir -p "${PERSIST_DIR}/codex_accounts" || true
    mkdir -p "${PERSIST_DIR}/codex_agent_accounts" || true

    # 1) 配置持久化：启动时从 /mnt/workspace 恢复 .env，后台定时同步回持久盘
    if [ -f "${PERSIST_DIR}/.env" ]; then
        echo "  - 从持久目录恢复 .env 配置"
        cp -f "${PERSIST_DIR}/.env" /app/.env || true
    fi

    # 2) 数据库持久化：SQLite 必须在本地容器文件系统运行，防止 OSSFS 锁冲突；启动恢复 + 退出/定时同步
    if [ -f "${PERSIST_DIR}/turb.sqlite3" ]; then
        echo "  - 从持久目录恢复 SQLite 数据库 turb.sqlite3"
        cp -f "${PERSIST_DIR}/turb.sqlite3" /app/turb.sqlite3 || true
    fi

    # 3) 日志与凭证软链
    rm -rf /app/注册日志 /app/codex_accounts /app/codex_agent_accounts || true
    ln -sf "${PERSIST_DIR}/注册日志" /app/注册日志 || true
    ln -sf "${PERSIST_DIR}/codex_accounts" /app/codex_accounts || true
    ln -sf "${PERSIST_DIR}/codex_agent_accounts" /app/codex_agent_accounts || true

    # 4) 后台数据看护同步循环（每 10 秒自动将 .env 和 turb.sqlite3 同步到持久盘）
    (
        while true; do
            sleep 10
            if [ -f "/app/.env" ]; then
                cp -f /app/.env "${PERSIST_DIR}/.env" 2>/dev/null || true
            fi
            if [ -f "/app/turb.sqlite3" ]; then
                cp -f /app/turb.sqlite3 "${PERSIST_DIR}/turb.sqlite3" 2>/dev/null || true
            fi
        done
    ) &

    echo "✓ 持久化恢复与看护进程已就绪"
else
    echo "[0/3] 未检测到 /mnt/workspace，使用容器本地存储"
fi

# 1. 启动 Xvfb 虚拟显示服务器
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
