#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Apple Sign In - Client Secret Generator
生成 Apple Sign In 所需的 Client Secret JWT
"""

import sys

# 检查依赖
try:
    import jwt
except ImportError:
    print("❌ 缺少 PyJWT 库")
    print("请运行以下命令安装：")
    print("  pip3 install PyJWT")
    print("\n或者：")
    print("  pip3 install PyJWT cryptography")
    sys.exit(1)

import time
from pathlib import Path

# ==================== 配置信息 ====================
# 请替换为您的实际信息
TEAM_ID = "B2LAVCCYQM"
CLIENT_ID = "lyl.WeItems"  # Service ID
KEY_ID = "9QNZ5S5Y4J"
PRIVATE_KEY_PATH = Path(__file__).parent / "sec.p8"

# JWT 有效期（天数），最长 180 天
EXPIRATION_DAYS = 180
# ==================================================

def generate_client_secret():
    """生成 Apple Client Secret JWT"""

    # 检查私钥文件是否存在
    key_file = Path(PRIVATE_KEY_PATH)
    if not key_file.exists():
        print(f"❌ 错误：找不到私钥文件 '{PRIVATE_KEY_PATH}'")
        print(f"   当前目录：{Path.cwd()}")
        print("\n请确保：")
        print("1. 已从 Apple Developer 下载 .p8 私钥文件")
        print("2. 将文件放在脚本同目录下，或修改 PRIVATE_KEY_PATH 为正确路径")
        sys.exit(1)

    # 读取私钥
    try:
        with open(PRIVATE_KEY_PATH, 'r') as f:
            private_key = f.read()
    except Exception as e:
        print(f"❌ 读取私钥文件失败：{e}")
        sys.exit(1)

    # 检查配置是否已修改
    if TEAM_ID == "YOUR_TEAM_ID" or CLIENT_ID == "com.yourcompany.service" or KEY_ID == "YOUR_KEY_ID":
        print("⚠️  警告：请先修改脚本中的配置信息！")
        print("\n需要配置的信息：")
        print(f"  - TEAM_ID: {TEAM_ID}")
        print(f"  - CLIENT_ID: {CLIENT_ID}")
        print(f"  - KEY_ID: {KEY_ID}")
        print(f"  - PRIVATE_KEY_PATH: {PRIVATE_KEY_PATH}")
        print("\n这些信息可以从 Apple Developer 后台获取")
        sys.exit(1)

    # 构造 JWT Header
    headers = {
        "kid": KEY_ID,
        "alg": "ES256"
    }

    # 构造 JWT Payload
    now = int(time.time())
    expiration = now + (86400 * EXPIRATION_DAYS)  # 86400 秒 = 1 天

    payload = {
        "iss": TEAM_ID,
        "iat": now,
        "exp": expiration,
        "aud": "https://appleid.apple.com",
        "sub": CLIENT_ID
    }

    # 生成 JWT
    try:
        client_secret = jwt.encode(
            payload,
            private_key,
            algorithm="ES256",
            headers=headers
        )

        # PyJWT 2.0+ 返回字符串，旧版本返回 bytes
        if isinstance(client_secret, bytes):
            client_secret = client_secret.decode('utf-8')

        return client_secret, expiration

    except Exception as e:
        print(f"❌ 生成 JWT 失败：{e}")
        print("\n可能的原因：")
        print("1. 私钥格式不正确")
        print("2. 缺少 cryptography 库，请运行：pip3 install cryptography")
        sys.exit(1)

def main():
    print("=" * 60)
    print("🍎 Apple Sign In - Client Secret Generator")
    print("=" * 60)
    print()

    print("📋 配置信息：")
    print(f"  Team ID:     {TEAM_ID}")
    print(f"  Client ID:   {CLIENT_ID}")
    print(f"  Key ID:      {KEY_ID}")
    print(f"  Private Key: {PRIVATE_KEY_PATH}")
    print(f"  有效期:      {EXPIRATION_DAYS} 天")
    print()

    print("🔄 正在生成 Client Secret...")
    client_secret, expiration = generate_client_secret()

    print("✅ 生成成功！")
    print()
    print("=" * 60)
    print("📝 Client Secret (JWT):")
    print("=" * 60)
    print(client_secret)
    print("=" * 60)
    print()

    # 显示过期时间
    from datetime import datetime
    expiration_date = datetime.fromtimestamp(expiration)
    print(f"⏰ 过期时间：{expiration_date.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"   （{EXPIRATION_DAYS} 天后）")
    print()

    print("💡 使用说明：")
    print("1. 复制上面的 JWT 字符串")
    print("2. 在 Provider 配置中，将其设置为 'client_secret' 字段的值")
    print("3. 在过期前需要重新生成新的 Client Secret")
    print()

if __name__ == "__main__":
    main()
