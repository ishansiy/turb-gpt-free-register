# syntax=docker/dockerfile:1
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    DISPLAY=:99

# 1. 安装基础系统工具、Xvfb (有头虚拟显示)、Chromium/GUI 依赖、中文字体、Node.js
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        gnupg \
        unzip \
        xvfb \
        xauth \
        x11-apps \
        fonts-liberation \
        fonts-noto-cjk \
        fonts-wqy-zenhei \
        libnss3 \
        libnspr4 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libasound2 \
        libpango-1.0-0 \
        libcairo2 \
        libglib2.0-0 \
        libx11-xcb1 \
        libxcb-dri3-0 \
        ffmpeg \
        procps \
    && rm -rf /var/lib/apt/lists/*

# 2. 安装 Node.js 18 (用于 sentinel / sdk.js challenge 执行)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. 安装 Python 依赖
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir playwright playwright-stealth cloakbrowser

# 4. 安装 Playwright Chromium 二进制
RUN playwright install chromium --with-deps || playwright install chromium

# 5. 复制全部业务代码与启动脚本
COPY . /app

RUN chmod +x /app/start.sh

EXPOSE 7860

CMD ["/app/start.sh"]
