#!/usr/bin/env bash
set -eo pipefail

echo "=================================================="
echo "🚀 启动 Turb GPT Free Register (ModelScope Studio)"
echo "=================================================="

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

# 2.5 启动 l2hero SMS 转译服务（SMS_PROVIDER=l → hero-sms 的本地转译层）
echo "[2.5/3] 启动 l2hero SMS 转译服务 (127.0.0.1:8799)..."
if ! pgrep -f "python.*l2hero/server.py" >/dev/null 2>&1; then
    python /app/l2hero/server.py >>/tmp/l2hero.log 2>&1 &
    sleep 1
fi
if curl -sf -o /dev/null --max-time 3 http://127.0.0.1:8799/health; then
    echo "✓ l2hero 就绪"
else
    echo "⚠ l2hero 未就绪（SMS 手机验证将不可用），日志: /tmp/l2hero.log"
fi

# 3. 启动 WebUI
echo "[3/3] 启动 WebUI 服务..."
exec python web.py --host "${HOST}" --port "${PORT}"
