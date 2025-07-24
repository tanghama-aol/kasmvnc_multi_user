#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KasmVNC多用户管理系统 - Nuitka打包脚本
作者: Xander Xu
"""

import os
import sys
import shutil
import subprocess
import tempfile
from pathlib import Path


def download_bootstrap_resources():
    """下载Bootstrap相关资源到本地"""
    import urllib.request
    
    resources = {
        'css/bootstrap.min.css': 'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css',
        'css/bootstrap-icons.css': 'https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css',
        'js/bootstrap.bundle.min.js': 'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js'
    }
    
    static_dir = Path('static')
    static_dir.mkdir(exist_ok=True)
    
    for local_path, url in resources.items():
        local_file = static_dir / local_path
        local_file.parent.mkdir(parents=True, exist_ok=True)
        
        if not local_file.exists():
            print(f"下载 {url} -> {local_file}")
            try:
                urllib.request.urlretrieve(url, local_file)
                print(f"✅ 下载成功: {local_file}")
            except Exception as e:
                print(f"❌ 下载失败: {e}")
                # 创建空文件以避免错误
                local_file.touch()
        else:
            print(f"📁 已存在: {local_file}")
    
    # 下载Bootstrap Icons字体文件
    fonts_dir = static_dir / 'fonts'
    fonts_dir.mkdir(exist_ok=True)
    
    font_files = {
        'bootstrap-icons.woff': 'https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/fonts/bootstrap-icons.woff',
        'bootstrap-icons.woff2': 'https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/fonts/bootstrap-icons.woff2'
    }
    
    for font_file, url in font_files.items():
        local_font = fonts_dir / font_file
        if not local_font.exists():
            print(f"下载字体 {url} -> {local_font}")
            try:
                urllib.request.urlretrieve(url, local_font)
                print(f"✅ 字体下载成功: {local_font}")
            except Exception as e:
                print(f"❌ 字体下载失败: {e}")
    
    # 修复CSS文件中的字体路径
    css_file = static_dir / 'css/bootstrap-icons.css'
    if css_file.exists():
        print("🔧 修复CSS字体路径...")
        with open(css_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 替换字体路径
        content = content.replace(
            'https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/fonts/',
            '../fonts/'
        )
        
        with open(css_file, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print("✅ CSS路径修复完成")


def build_with_nuitka():
    """使用Nuitka打包应用"""
    print("🔨 开始Nuitka打包...")
    
    # 检查Nuitka是否安装
    try:
        subprocess.run(['nuitka', '--version'], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 未找到Nuitka，请先安装: pip install nuitka")
        return False
    
    # 构建命令
    build_cmd = [
        'nuitka',
        '--standalone',
        '--onefile',
        '--enable-plugin=multiprocessing',
        '--include-data-dir=static=static',
        '--include-data-dir=templates=templates',
        '--include-package=app',
        '--include-package=uvicorn',
        '--include-package=fastapi',
        '--include-package=jinja2',
        '--include-package=psutil',
        '--python-flag=no_site',
        '--output-filename=kasmvnc-manager',
        '--output-dir=dist',
        'run.py'
    ]
    
    print(f"执行命令: {' '.join(build_cmd)}")
    
    try:
        # 执行打包
        result = subprocess.run(build_cmd, check=True, capture_output=True, text=True)
        print("✅ Nuitka打包成功！")
        print(f"📦 输出文件: dist/kasmvnc-manager")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Nuitka打包失败:")
        print(f"stdout: {e.stdout}")
        print(f"stderr: {e.stderr}")
        return False


def build_with_pyinstaller():
    """使用PyInstaller打包应用（备选方案）"""
    print("🔨 开始PyInstaller打包...")
    
    # 检查PyInstaller是否安装
    try:
        subprocess.run(['pyinstaller', '--version'], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 未找到PyInstaller，请先安装: pip install pyinstaller")
        return False
    
    # 创建spec文件
    spec_content = '''
# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['run.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('static', 'static'),
        ('templates', 'templates'),
        ('app', 'app'),
    ],
    hiddenimports=[
        'uvicorn.lifespan.on',
        'uvicorn.lifespan.off',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.websockets.websockets_impl',
        'uvicorn.protocols.http.httptools_impl',
        'uvicorn.protocols.http.h11_impl',
        'uvicorn.loops.auto',
        'uvicorn.loops.asyncio',
        'uvicorn.logging',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='kasmvnc-manager',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
'''
    
    with open('kasmvnc-manager.spec', 'w', encoding='utf-8') as f:
        f.write(spec_content)
    
    build_cmd = ['pyinstaller', '--clean', 'kasmvnc-manager.spec']
    
    print(f"执行命令: {' '.join(build_cmd)}")
    
    try:
        result = subprocess.run(build_cmd, check=True, capture_output=True, text=True)
        print("✅ PyInstaller打包成功！")
        print(f"📦 输出文件: dist/kasmvnc-manager")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ PyInstaller打包失败:")
        print(f"stdout: {e.stdout}")
        print(f"stderr: {e.stderr}")
        return False


def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description='KasmVNC多用户管理系统打包工具')
    parser.add_argument('--tool', choices=['nuitka', 'pyinstaller'], default='nuitka',
                       help='打包工具选择 (默认: nuitka)')
    parser.add_argument('--download-only', action='store_true',
                       help='仅下载资源文件，不进行打包')
    parser.add_argument('--skip-download', action='store_true',
                       help='跳过资源下载，直接打包')
    
    args = parser.parse_args()
    
    print("🏗️  KasmVNC多用户管理系统 - 构建工具")
    print("=" * 50)
    
    # 下载资源文件
    if not args.skip_download:
        print("📥 下载前端资源...")
        download_bootstrap_resources()
        print("✅ 资源下载完成\n")
    
    if args.download_only:
        print("✅ 仅下载模式完成")
        return
    
    # 检查必要文件
    required_files = ['run.py', 'app/main.py', 'static/css/style.css']
    for file_path in required_files:
        if not Path(file_path).exists():
            print(f"❌ 缺少必要文件: {file_path}")
            return
    
    # 选择打包工具
    if args.tool == 'nuitka':
        success = build_with_nuitka()
    else:
        success = build_with_pyinstaller()
    
    if success:
        print("\n✅ 打包完成！")
        print(f"📦 可执行文件位于: dist/kasmvnc-manager")
        print(f"🚀 运行方式: ./dist/kasmvnc-manager --help")
    else:
        print("\n❌ 打包失败")
        sys.exit(1)


if __name__ == "__main__":
    main()