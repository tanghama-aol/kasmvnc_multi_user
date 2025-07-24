#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KasmVNC多用户管理系统 - 启动脚本
作者: Xander Xu
"""

import os
import sys
import uvicorn
import argparse
from pathlib import Path

# 添加应用目录到Python路径
app_dir = Path(__file__).parent
sys.path.insert(0, str(app_dir))

from app.main import app


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='KasmVNC多用户管理系统')
    parser.add_argument('--host', default='0.0.0.0', help='绑定地址 (默认: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=8000, help='端口号 (默认: 8000)')
    parser.add_argument('--reload', action='store_true', help='启用自动重载 (开发模式)')
    parser.add_argument('--log-level', default='info', 
                       choices=['debug', 'info', 'warning', 'error'],
                       help='日志级别 (默认: info)')
    parser.add_argument('--workers', type=int, default=1, help='工作进程数 (默认: 1)')
    
    args = parser.parse_args()
    
    print("🚀 启动KasmVNC多用户管理系统...")
    print(f"📡 服务地址: http://{args.host}:{args.port}")
    print(f"📝 API文档: http://{args.host}:{args.port}/api/docs")
    print(f"🌐 Web界面: http://{args.host}:{args.port}")
    print("=" * 50)
    
    # 启动服务器
    uvicorn.run(
        "app.main:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level=args.log_level,
        workers=args.workers if not args.reload else 1,
        reload_dirs=["app"] if args.reload else None,
        access_log=True
    )


if __name__ == "__main__":
    main()