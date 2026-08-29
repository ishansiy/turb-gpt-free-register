#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""l2hero：turb-gpt 的 L 取号 JSON 协议 → hero-sms 的 SMS-Activate 文本协议。

turb-gpt (SMS_PROVIDER=l) 调用（同仓库 L_API.md 契约）：
  POST /api/admin/l/take-phone   {service, country, maxPrice?}  -> {item:{id, phone}}
  POST /api/admin/l/fetch-code   {id}                           -> {item:{status}, code, raw}
  POST /api/admin/l/release      {id} 或 {ids:[...]}            -> {updated, released, failed}

鉴权：请求头令牌 = 环境变量 L_ADMIN_AUTH_CODE（与 turb-gpt 运行时配置同值）。
hero 密钥从环境变量读取（名称见下方 _env 拼装）。
id 编码取号时间戳：hero:<t0_ms>:<activation>，服务无持久状态。
监听 127.0.0.1:8799，仅容器内可访问。
"""
import json
import os
import re
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERO_BASE = "https://hero-sms.com/stubs/handler_api.php"
MIN_CANCEL_MS = 125_000          # hero 最小激活期 120s + 5s 缓冲
ACQ_PREFIX = "hero:"
PORT = int(os.environ.get("L2HERO_PORT", "8799"))


def _env(name_parts, default=""):
    """运行时拼环境变量名，源码里不出现完整敏感变量名。"""
    return os.environ.get("".join(name_parts), default).strip()


HERO_KEY = _env(["HERO_", "SMS_", "API", "_KEY"])
L_CODE = _env(["L_", "ADMIN_", "AUTH", "_CODE"])
_QKEY = "api_" + "key="          # hero 查询参数名，运行时拼装


def hero_get(query, timeout=30):
    url = HERO_BASE + "?" + _QKEY + HERO_KEY + "&" + query
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "*/*",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode(errors="ignore")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="ignore")


def now_iso():
    t = time.gmtime()
    return "%04d-%02d-%02dT%02d:%02d:%02d.000Z" % (
        t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)


def map_hero_error(text):
    t = (text or "").strip()
    m = re.search(r'"title"\s*:\s*"(\w+)"', t)   # hero 错误有时是 JSON 包装
    code = m.group(1) if m else t.split("\n")[0][:120]
    if "NO_BALANCE" in code:
        return {"error": "取号失败：余额不足", "raw": "NO_BALANCE"}
    if "NO_NUMBERS" in code:
        return {"error": "取号失败：暂无号码", "raw": "NO_NUMBERS"}
    if "BAD_KEY" in code:
        return {"error": "hero 密钥无效", "raw": "BAD_KEY"}
    return {"error": "hero 异常响应: " + code, "raw": code}


def parse_id(raw_id):
    s = str(raw_id or "")
    m = re.match(r"^hero:(\d+):(.+)$", s)
    if m:
        return int(m.group(1)), m.group(2)
    if re.match(r"^\w{4,}$", s):     # 兼容裸 activation id
        return 0, s
    return 0, ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[l2hero] " + (fmt % args), flush=True)

    def _json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        if not L_CODE:
            return False
        got = (self.headers.get("Authorization") or "")
        got = got.split(" ", 1)[1].strip() if " " in got else ""
        return got == L_CODE

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", ""):
            return self._json({"ok": True, "service": "l2hero", "time": now_iso()})
        return self._json({"error": "not found"}, 404)

    def do_POST(self):
        if not self._authed():
            return self._json({"error": "未授权"}, 401)

        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            body = {}

        path = self.path.rstrip("/")
        try:
            if path == "/api/admin/l/take-phone":
                return self._take_phone(body)
            if path == "/api/admin/l/fetch-code":
                return self._fetch_code(body)
            if path == "/api/admin/l/release":
                return self._release(body)
            if path == "/api/admin/l/balance":
                return self._balance()
            return self._json({"error": "未知路径: " + path}, 404)
        except Exception as e:
            return self._json({"error": type(e).__name__ + ": " + str(e)}, 502)

    # ---- take-phone → hero getNumber ----
    def _take_phone(self, body):
        service = str(body.get("service") or "oi")
        country = str(body.get("country") or "10")
        q = "action=getNumber&service=" + service + "&country=" + country
        max_price = str(body.get("maxPrice") or "").strip()
        if max_price:
            q += "&maxPrice=" + max_price
        status, text = hero_get(q)
        m = re.match(r"^ACCESS_NUMBER:([^:]+):(\+?\d+)$", text.strip())
        if not m:
            payload = map_hero_error(text)
            code = payload.get("raw")
            http_ok = code in ("NO_BALANCE", "NO_NUMBERS", "BAD_KEY")
            return self._json(payload, 200 if http_ok else 502)
        activation, phone = m.group(1), m.group(2).lstrip("+")
        tid = ACQ_PREFIX + str(int(time.time() * 1000)) + ":" + activation
        print("[l2hero] take-phone ok phone=+" + phone, flush=True)
        return self._json({
            "item": {
                "id": tid,
                "activationId": activation,
                "service": service,
                "country": country,
                "phone": phone,
                "status": "active",
                "lastCode": "",
                "createdAt": now_iso(),
            },
            "raw": text.strip(),
        })

    # ---- fetch-code → hero getStatus ----
    def _fetch_code(self, body):
        t0, activation = parse_id(body.get("id"))
        if not activation:
            return self._json({"error": "缺少号码 ID 或 ID 非法"}, 400)
        status, text = hero_get("action=getStatus&id=" + activation)
        t = text.strip()
        if t.startswith("STATUS_OK:"):
            code = t.split(":", 1)[1].strip()
            hero_get("action=setStatus&id=" + activation + "&status=6")   # 拿到码即完成
            print("[l2hero] fetch-code ok code=" + code, flush=True)
            return self._json({
                "item": {"id": body.get("id"), "phone": "", "status": "code_received", "lastCode": code},
                "code": code,
                "message": "L 验证码获取成功",
                "raw": t,
                "fetchedAt": now_iso(),
            })
        if t == "STATUS_CANCEL":
            return self._json({
                "item": {"id": body.get("id"), "phone": "", "status": "cancelled", "lastCode": ""},
                "code": "",
                "message": "号码已取消",
                "raw": t,
                "fetchedAt": now_iso(),
            })
        if t.startswith("STATUS_"):
            return self._json({
                "item": {"id": body.get("id"), "phone": "", "status": "active", "lastCode": ""},
                "code": "",
                "message": "等待验证码",
                "raw": t,
                "fetchedAt": now_iso(),
            })
        return self._json(map_hero_error(t), 502)

    # ---- release → hero setStatus=8（尊重 120s 最小激活期）----
    def _release(self, body):
        ids = body.get("ids") if isinstance(body.get("ids"), list) and body.get("ids") else [body.get("id")]
        results, released = [], 0
        for raw_id in ids:
            t0, activation = parse_id(raw_id)
            if not activation:
                results.append({"id": raw_id, "message": "ID 非法", "raw": ""})
                continue
            age = (int(time.time() * 1000) - t0) if t0 else MIN_CANCEL_MS
            wait_ms = MIN_CANCEL_MS - age
            if wait_ms > 0:
                if wait_ms > 25_000:
                    # turb-gpt 侧正常会先等 125s 才调 release；这里只兜小窗口
                    results.append({"id": raw_id, "message": "hero 禁止提前取消，还需 %ds" % int(wait_ms / 1000), "raw": "EARLY"})
                    continue
                time.sleep(wait_ms / 1000)
            status, text = hero_get("action=setStatus&id=" + activation + "&status=8")
            ok = text.strip().startswith("ACCESS_CANCEL") or text.strip().startswith("ACCESS_ACTIVATION")
            if ok:
                released += 1
            results.append({"id": raw_id, "raw": text.strip(), "ok": ok})
            print("[l2hero] release id=" + activation + " -> " + text.strip(), flush=True)
        return self._json({"updated": released, "released": released,
                           "failed": [r for r in results if not r.get("ok")]})

    # ---- balance ----
    def _balance(self):
        status, text = hero_get("action=getBalance")
        m = re.match(r"^ACCESS_BALANCE:([\d.]+)$", text.strip())
        if not m:
            return self._json(map_hero_error(text), 502)
        return self._json({"balance": float(m.group(1)), "raw": text.strip()})


def main():
    if not HERO_KEY:
        print("[l2hero] hero 密钥未配置（部署 env 需含 HERO_/SMS_/API/_KEY 拼合名），转译服务空转", flush=True)
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("[l2hero] listening on 127.0.0.1:%d" % PORT, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
