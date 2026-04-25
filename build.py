#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WeItems iOS 一键构建脚本
用法: python3 build.py [--clean] [--no-export] [--app-store]
"""

import subprocess
import sys
import os
import shutil
import time
import re
import plistlib
from pathlib import Path

# ==================== 配置 ====================
PROJECT_DIR = Path(__file__).parent
PROJECT_FILE = PROJECT_DIR / "WeItems.xcodeproj"
PBXPROJ_PATH = PROJECT_FILE / "project.pbxproj"
SCHEME = "WeItems"
TEAM_ID = "B2LAVCCYQM"
BUILD_DIR = PROJECT_DIR / "build"
ARCHIVE_PATH = BUILD_DIR / "WeItems.xcarchive"
EXPORT_DIR = BUILD_DIR / "ipa"
EXPORT_PLIST = BUILD_DIR / "ExportOptions.plist"
# ==============================================


def run(cmd, desc=None, check=True, capture=False):
    """执行命令"""
    if desc:
        print(f"\n{'='*50}")
        print(f"  {desc}")
        print(f"{'='*50}")

    if capture:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if check and result.returncode != 0:
            print(f"❌ 失败: {result.stderr or result.stdout}")
            sys.exit(1)
        return result
    else:
        result = subprocess.run(cmd, shell=True)
        if check and result.returncode != 0:
            print(f"❌ 命令执行失败 (exit {result.returncode})")
            sys.exit(1)
        return result


def check_env():
    """检查编译环境"""
    print("🔍 检查编译环境...")

    # 检查 xcodebuild
    result = run("which xcodebuild", capture=True, check=False)
    if result.returncode != 0:
        print("❌ 未找到 xcodebuild，请安装 Xcode")
        sys.exit(1)

    # 检查 xcode-select 路径
    result = run("xcode-select -p", capture=True)
    dev_path = result.stdout.strip()
    if "CommandLineTools" in dev_path:
        print(f"⚠️  当前 developer 目录: {dev_path}")
        print("   需要切换到 Xcode.app，请运行:")
        print("   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")
        sys.exit(1)

    print(f"  ✅ Xcode 路径: {dev_path}")

    # 打印 Xcode 版本
    result = run("xcodebuild -version | head -2", capture=True)
    for line in result.stdout.strip().split("\n"):
        print(f"  ✅ {line}")

    # 检查项目文件
    if not PROJECT_FILE.exists():
        print(f"❌ 未找到项目文件: {PROJECT_FILE}")
        sys.exit(1)
    print(f"  ✅ 项目: {PROJECT_FILE.name}")


def clean_build():
    """清理构建产物"""
    print("\n🧹 清理构建产物...")
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
        print(f"  已删除 {BUILD_DIR}")
    run(
        f'cd "{PROJECT_DIR}" && xcodebuild clean -project {PROJECT_FILE.name} -scheme {SCHEME} -configuration Release 2>/dev/null',
        check=False,
        capture=True
    )
    print("  ✅ 清理完成")


def increment_build_number():
    """读取并自增 CURRENT_PROJECT_VERSION，version 变更时重置为 1"""
    content = PBXPROJ_PATH.read_text(encoding="utf-8")

    # 读取当前 MARKETING_VERSION
    version_match = re.search(r'MARKETING_VERSION\s*=\s*([^;]+);', content)
    if not version_match:
        print("⚠️  未找到 MARKETING_VERSION，跳过自增")
        return
    marketing_version = version_match.group(1).strip()

    # 读取当前 BUILD_NUMBER
    build_pattern = re.compile(r'(CURRENT_PROJECT_VERSION\s*=\s*)(\d+)(;)')
    build_matches = build_pattern.findall(content)
    if not build_matches:
        print("⚠️  未找到 CURRENT_PROJECT_VERSION，跳过自增")
        return
    old_num = int(build_matches[0][1])

    # 检查 version 是否变更
    version_file = PROJECT_DIR / ".last_marketing_version"
    last_version = ""
    if version_file.exists():
        last_version = version_file.read_text().strip()

    if marketing_version != last_version:
        # version 变更，重置为 1
        new_num = 1
        print(f"  📌 Version changed: {last_version or '(none)'} → {marketing_version}, reset build to 1")
    else:
        # version 未变更，+1
        new_num = old_num + 1
        print(f"  ✅ Build Number: {old_num} → {new_num}")

    def replacer(m):
        return f'{m.group(1)}{new_num}{m.group(3)}'

    new_content = build_pattern.sub(replacer, content)
    PBXPROJ_PATH.write_text(new_content, encoding="utf-8")

    # 记录当前 version
    version_file.write_text(marketing_version, encoding="utf-8")


def archive():
    """编译 Release Archive（带进度条）"""
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # 删除旧 archive
    if ARCHIVE_PATH.exists():
        shutil.rmtree(ARCHIVE_PATH)

    # 先通过 dry-run 获取总编译文件数（用于进度估算）
    dry_cmd = (
        f'cd "{PROJECT_DIR}" && xcodebuild '
        f'-project {PROJECT_FILE.name} '
        f'-scheme {SCHEME} '
        f'-configuration Release '
        f'-sdk iphoneos '
        f'-dry-run '
        f'archive '
        f'CODE_SIGNING_ALLOWED=YES '
        f'CODE_SIGN_STYLE=Automatic '
        f'DEVELOPMENT_TEAM={TEAM_ID} 2>&1'
    )
    dry_result = subprocess.run(dry_cmd, shell=True, capture_output=True, text=True)
    # 估算总步骤数：匹配 CompileSwift / CompileC / Ld / CodeSign 等
    step_pattern = re.compile(r'^(CompileSwift|CompileC|Ld|LinkStoryboards|CodeSign|ProcessInfoPlistFile|CopySwiftLibs|GenerateAssetSymbols|CompileAssetCatalog|ProcessProductPackaging|RegisterExecutionPolicyException|Validate|Touch|MergeSwiftModule)\s', re.MULTILINE)
    estimated_steps = len(step_pattern.findall(dry_result.stdout))
    if estimated_steps == 0:
        estimated_steps = 50  # fallback 估算

    cmd = (
        f'cd "{PROJECT_DIR}" && xcodebuild '
        f'-project {PROJECT_FILE.name} '
        f'-scheme {SCHEME} '
        f'-configuration Release '
        f'-sdk iphoneos '
        f'-archivePath "{ARCHIVE_PATH}" '
        f'archive '
        f'CODE_SIGNING_ALLOWED=YES '
        f'CODE_SIGN_STYLE=Automatic '
        f'DEVELOPMENT_TEAM={TEAM_ID} 2>&1'
    )

    print(f"\n{'='*50}")
    print(f"  🔨 编译 Release Archive")
    print(f"{'='*50}")

    start = time.time()
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    completed_steps = 0
    current_file = ""
    current_phase = ""
    bar_width = 30
    last_error_lines = []

    # 阶段友好名映射
    phase_names = {
        "CompileSwift": "编译 Swift",
        "CompileC": "编译 C/ObjC",
        "Ld": "链接",
        "LinkStoryboards": "链接 Storyboard",
        "CodeSign": "代码签名",
        "ProcessInfoPlistFile": "处理 Info.plist",
        "CopySwiftLibs": "拷贝 Swift 库",
        "GenerateAssetSymbols": "生成资源符号",
        "CompileAssetCatalog": "编译资源目录",
        "ProcessProductPackaging": "处理产品打包",
        "RegisterExecutionPolicyException": "注册执行策略",
        "Validate": "验证",
        "Touch": "Touch",
        "MergeSwiftModule": "合并 Swift 模块",
    }

    for line in process.stdout:
        line = line.rstrip('\n')
        last_error_lines.append(line)
        if len(last_error_lines) > 20:
            last_error_lines.pop(0)

        match = step_pattern.match(line)
        if match:
            completed_steps += 1
            current_phase = match.group(1)

            # 提取文件名
            parts = line.split()
            for part in reversed(parts):
                if '.' in part and '/' in part:
                    current_file = Path(part).name
                    break
                elif part.endswith('.swift') or part.endswith('.m') or part.endswith('.c'):
                    current_file = part
                    break
            else:
                current_file = ""

            # 计算进度
            progress = min(completed_steps / estimated_steps, 0.99)
            filled = int(bar_width * progress)
            bar = '█' * filled + '░' * (bar_width - filled)
            pct = progress * 100
            phase_display = phase_names.get(current_phase, current_phase)
            file_display = f" {current_file}" if current_file else ""
            elapsed = time.time() - start

            status = f"\r  [{bar}] {pct:5.1f}% | {phase_display}{file_display} ({elapsed:.0f}s)"
            # 截断避免终端换行
            term_width = shutil.get_terminal_size().columns
            if len(status) > term_width:
                status = status[:term_width - 1]
            print(status, end='', flush=True)

    process.wait()

    # 完成进度条
    elapsed = time.time() - start
    bar = '█' * bar_width
    print(f"\r  [{bar}] 100.0% | 完成 ({elapsed:.0f}s){' ' * 20}")

    if process.returncode != 0:
        print(f"❌ Archive 编译失败 (exit {process.returncode})")
        print("  最后输出:")
        for l in last_error_lines[-10:]:
            print(f"    {l}")
        sys.exit(1)

    if not ARCHIVE_PATH.exists():
        print("❌ Archive 生成失败")
        sys.exit(1)

    print(f"  ✅ Archive 完成 ({elapsed:.1f}s)")
    print(f"  📁 {ARCHIVE_PATH}")


def create_export_plist(method="ad-hoc"):
    """生成导出配置"""
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    plist = {
        "method": method,
        "teamID": TEAM_ID,
        "signingStyle": "automatic",
        "stripSwiftSymbols": True,
        "compileBitcode": False,
    }

    if method == "app-store":
        plist["uploadSymbols"] = True
        plist["destination"] = "upload"

    with open(EXPORT_PLIST, "wb") as f:
        plistlib.dump(plist, f)

    print(f"  ✅ 导出配置: {method}")


def export_ipa():
    """导出 IPA"""
    if EXPORT_DIR.exists():
        shutil.rmtree(EXPORT_DIR)

    cmd = (
        f'xcodebuild -exportArchive '
        f'-archivePath "{ARCHIVE_PATH}" '
        f'-exportOptionsPlist "{EXPORT_PLIST}" '
        f'-exportPath "{EXPORT_DIR}"'
    )

    start = time.time()
    run(cmd, desc="📦 导出 IPA")
    elapsed = time.time() - start

    # 查找 IPA 文件
    ipa_files = list(EXPORT_DIR.glob("*.ipa"))
    if not ipa_files:
        print("❌ IPA 导出失败，未找到 .ipa 文件")
        sys.exit(1)

    ipa_path = ipa_files[0]
    ipa_size = ipa_path.stat().st_size / (1024 * 1024)

    print(f"\n  ✅ 导出完成 ({elapsed:.1f}s)")
    print(f"  📱 {ipa_path}")
    print(f"  📏 {ipa_size:.1f} MB")

    return ipa_path


def main():
    args = sys.argv[1:]
    do_clean = "--clean" in args
    no_export = "--no-export" in args
    app_store = "--app-store" in args
    method = "app-store" if app_store else "ad-hoc"

    print("=" * 50)
    print("  🍎 WeItems iOS 构建脚本")
    print("=" * 50)

    total_start = time.time()

    # 1. 检查环境
    check_env()

    # 2. 清理（可选）
    if do_clean:
        clean_build()

    # 3. 自增 Build Number
    increment_build_number()

    # 4. 编译 Archive
    archive()

    # 5. 导出 IPA
    if not no_export:
        create_export_plist(method=method)
        ipa_path = export_ipa()

    total_elapsed = time.time() - total_start

    print(f"\n{'='*50}")
    print(f"  ✅ 全部完成！耗时 {total_elapsed:.1f}s")
    if not no_export:
        print(f"  📱 IPA: {ipa_path}")
    print(f"{'='*50}")
    if not no_export:
        print(f"\n{ipa_path.resolve()}")


if __name__ == "__main__":
    main()
