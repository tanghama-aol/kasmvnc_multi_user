#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KasmVNC多用户管理系统 - FastAPI主应用
作者: Xander Xu
"""

import os
import time
from typing import List, Optional
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from .models import (
    VNCUser, CreateUserRequest, ServiceControlRequest, DesktopSyncRequest,
    SystemStatus, ApiResponse, ConfigSettings, ServiceInfo, BatchOperationResult,
    OperationLog
)
from .vnc_manager import VNCManager

# 应用配置
VERSION = "1.0.0"
TITLE = "KasmVNC多用户管理系统"
DESCRIPTION = """
KasmVNC多用户管理系统提供了完整的VNC用户管理解决方案。

## 主要功能

* **用户管理**: 批量创建和管理VNC用户
* **服务控制**: 启动、停止和监控VNC服务
* **桌面同步**: 同步桌面配置和应用程序
* **系统监控**: 实时监控系统状态和资源使用
* **Web界面**: 美观实用的管理界面

## API功能

* 用户管理API
* 服务控制API  
* 状态监控API
* 桌面同步API
"""

# 应用初始化
app = FastAPI(
    title=TITLE,
    description=DESCRIPTION,
    version=VERSION,
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

# CORS中间件
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 配置设置
config = ConfigSettings()

# VNC管理器实例
vnc_manager = VNCManager(config)

# 模板和静态文件
current_dir = Path(__file__).parent.parent
templates = Jinja2Templates(directory=str(current_dir / "templates"))
app.mount("/static", StaticFiles(directory=str(current_dir / "static")), name="static")

# 全局变量
app_start_time = time.time()


# 依赖注入
def get_vnc_manager() -> VNCManager:
    """获取VNC管理器实例"""
    return vnc_manager


def get_config() -> ConfigSettings:
    """获取配置设置"""
    return config


# API响应包装器
def success_response(data=None, message="操作成功"):
    """成功响应"""
    return ApiResponse(success=True, message=message, data=data)


def error_response(message="操作失败", data=None):
    """错误响应"""
    return ApiResponse(success=False, message=message, data=data)


# ============================================================================
# Web 页面路由
# ============================================================================

@app.get("/", response_class=HTMLResponse, summary="主页")
async def home_page(request: Request):
    """主页"""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "title": TITLE,
        "version": VERSION
    })


@app.get("/users", response_class=HTMLResponse, summary="用户管理页面")
async def users_page(request: Request):
    """用户管理页面"""
    return templates.TemplateResponse("users.html", {
        "request": request,
        "title": "用户管理"
    })


@app.get("/services", response_class=HTMLResponse, summary="服务管理页面")
async def services_page(request: Request):
    """服务管理页面"""
    return templates.TemplateResponse("services.html", {
        "request": request,
        "title": "服务管理"
    })


@app.get("/monitor", response_class=HTMLResponse, summary="系统监控页面")
async def monitor_page(request: Request):
    """系统监控页面"""
    return templates.TemplateResponse("monitor.html", {
        "request": request,
        "title": "系统监控"
    })


@app.get("/settings", response_class=HTMLResponse, summary="系统设置页面")
async def settings_page(request: Request):
    """系统设置页面"""
    return templates.TemplateResponse("settings.html", {
        "request": request,
        "title": "系统设置"
    })


# ============================================================================
# API 路由 - 用户管理
# ============================================================================

@app.post("/api/users/create", response_model=ApiResponse, summary="创建用户")
async def create_users(
    request: CreateUserRequest,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """
    批量创建VNC用户
    
    - **user_count**: 用户数量 (1-50)
    - **enable_https**: 是否启用HTTPS
    - **base_display**: 基础显示器编号
    - **base_port**: 基础端口号
    - **base_websocket_port**: 基础WebSocket端口
    """
    try:
        users = manager.create_users(request)
        return success_response(
            data={"users": [user.model_dump() for user in users]},
            message=f"成功创建 {len(users)} 个用户"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/users", response_model=ApiResponse, summary="获取用户列表")
async def get_users(manager: VNCManager = Depends(get_vnc_manager)):
    """获取所有用户列表"""
    try:
        users = manager.load_users_data()
        
        # 更新用户状态
        for user in users:
            for display in user.displays:
                proc = manager.get_process_by_display(display.display_number)
                if proc:
                    display.status = "running"
                    display.pid = proc.pid
                    user.last_active = time.time()
                else:
                    display.status = "stopped"
                    display.pid = None
        
        return success_response(
            data={"users": [user.model_dump() for user in users]},
            message=f"获取到 {len(users)} 个用户"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/users/{username}", response_model=ApiResponse, summary="获取用户详情")
async def get_user_detail(
    username: str,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """获取指定用户的详细信息"""
    try:
        users = manager.load_users_data()
        user = next((u for u in users if u.username == username), None)
        
        if not user:
            raise HTTPException(status_code=404, detail=f"用户 {username} 不存在")
        
        # 更新用户状态
        for display in user.displays:
            proc = manager.get_process_by_display(display.display_number)
            if proc:
                display.status = "running"
                display.pid = proc.pid
                user.last_active = time.time()
            else:
                display.status = "stopped"
                display.pid = None
        
        return success_response(
            data={"user": user.model_dump()},
            message=f"获取用户 {username} 信息成功"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/users/{username}", response_model=ApiResponse, summary="删除用户")
async def delete_user(
    username: str,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """删除指定用户"""
    try:
        # 先停止用户的所有VNC服务
        users = manager.load_users_data()
        user = next((u for u in users if u.username == username), None)
        
        if not user:
            raise HTTPException(status_code=404, detail=f"用户 {username} 不存在")
        
        # 停止所有显示器
        for display in user.displays:
            manager.stop_vnc_display(username, display.display_number)
        
        # 从用户列表中移除
        users = [u for u in users if u.username != username]
        manager.save_users_data(users)
        
        return success_response(message=f"用户 {username} 删除成功")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# API 路由 - 服务管理
# ============================================================================

@app.post("/api/services/control", response_model=ApiResponse, summary="控制服务")
async def control_service(
    request: ServiceControlRequest,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """
    控制VNC服务
    
    - **username**: 用户名
    - **display_number**: 显示器编号（可选，不指定则操作所有显示器）
    - **action**: 操作类型 (start, stop, restart)
    """
    try:
        users = manager.load_users_data()
        user = next((u for u in users if u.username == request.username), None)
        
        if not user:
            raise HTTPException(status_code=404, detail=f"用户 {request.username} 不存在")
        
        # 确定要操作的显示器
        displays_to_operate = []
        if request.display_number:
            display = next((d for d in user.displays if d.display_number == request.display_number), None)
            if display:
                displays_to_operate.append(display)
        else:
            displays_to_operate = user.displays
        
        if not displays_to_operate:
            raise HTTPException(status_code=400, detail="未找到要操作的显示器")
        
        results = []
        for display in displays_to_operate:
            display_num = display.display_number
            success = False
            
            if request.action == "start":
                success = manager.start_vnc_display(request.username, display_num)
            elif request.action == "stop":
                success = manager.stop_vnc_display(request.username, display_num)
            elif request.action == "restart":
                manager.stop_vnc_display(request.username, display_num)
                time.sleep(2)
                success = manager.start_vnc_display(request.username, display_num)
            else:
                raise HTTPException(status_code=400, detail=f"不支持的操作: {request.action}")
            
            results.append({
                "display": display_num,
                "action": request.action,
                "success": success
            })
        
        success_count = sum(1 for r in results if r["success"])
        
        return success_response(
            data={"results": results},
            message=f"{request.action} 操作完成，成功: {success_count}/{len(results)}"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/services/batch-control", response_model=ApiResponse, summary="批量控制服务")
async def batch_control_services(
    action: str,
    usernames: Optional[List[str]] = None,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """
    批量控制VNC服务
    
    - **action**: 操作类型 (start, stop, restart)
    - **usernames**: 用户名列表（可选，不指定则操作所有用户）
    """
    try:
        if action not in ["start", "stop", "restart"]:
            raise HTTPException(status_code=400, detail=f"不支持的操作: {action}")
        
        users = manager.load_users_data()
        
        # 确定要操作的用户
        if usernames:
            users = [u for u in users if u.username in usernames]
        
        if not users:
            raise HTTPException(status_code=400, detail="未找到要操作的用户")
        
        results = []
        total_displays = 0
        success_displays = 0
        
        for user in users:
            user_results = []
            
            for display in user.displays:
                total_displays += 1
                display_num = display.display_number
                success = False
                
                if action == "start":
                    success = manager.start_vnc_display(user.username, display_num)
                elif action == "stop":
                    success = manager.stop_vnc_display(user.username, display_num)
                elif action == "restart":
                    manager.stop_vnc_display(user.username, display_num)
                    time.sleep(1)
                    success = manager.start_vnc_display(user.username, display_num)
                
                if success:
                    success_displays += 1
                
                user_results.append({
                    "display": display_num,
                    "success": success
                })
            
            results.append({
                "username": user.username,
                "displays": user_results
            })
        
        return success_response(
            data={"results": results},
            message=f"批量 {action} 操作完成，成功: {success_displays}/{total_displays}"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# API 路由 - 系统监控
# ============================================================================

@app.get("/api/status", response_model=ApiResponse, summary="获取系统状态")
async def get_system_status(manager: VNCManager = Depends(get_vnc_manager)):
    """获取系统状态信息"""
    try:
        status = manager.get_system_status()
        return success_response(
            data={"status": status.model_dump()},
            message="获取系统状态成功"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/info", response_model=ApiResponse, summary="获取服务信息")
async def get_service_info(
    manager: VNCManager = Depends(get_vnc_manager),
    config: ConfigSettings = Depends(get_config)
):
    """获取服务基本信息"""
    try:
        # 检查依赖
        deps_ok, missing_deps = manager.check_dependencies()
        
        # 统计信息
        users = manager.load_users_data()
        logs = manager.get_operation_logs(limit=10)
        
        service_info = ServiceInfo(
            service_name=TITLE,
            version=VERSION,
            status="running" if deps_ok else "error",
            uptime=time.time() - app_start_time,
            config=config,
            statistics={
                "total_users": len(users),
                "dependencies_ok": deps_ok,
                "missing_dependencies": missing_deps,
                "recent_operations": len(logs)
            }
        )
        
        return success_response(
            data={"info": service_info.model_dump()},
            message="获取服务信息成功"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/logs", response_model=ApiResponse, summary="获取操作日志")
async def get_operation_logs(
    limit: int = 50,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """获取操作日志"""
    try:
        logs = manager.get_operation_logs(limit=limit)
        return success_response(
            data={"logs": [log.model_dump() for log in logs]},
            message=f"获取到 {len(logs)} 条日志"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# API 路由 - 桌面同步
# ============================================================================

@app.post("/api/desktop/sync", response_model=ApiResponse, summary="同步桌面")
async def sync_desktop(
    request: DesktopSyncRequest,
    manager: VNCManager = Depends(get_vnc_manager)
):
    """
    同步桌面配置
    
    - **source_user**: 源用户名
    - **target_users**: 目标用户列表（空列表表示所有用户）
    - **sync_desktop**: 是否同步桌面文件
    - **sync_icons**: 是否同步应用图标
    - **sync_autostart**: 是否同步自启动应用
    """
    try:
        results = manager.sync_desktop(
            source_user=request.source_user,
            target_users=request.target_users,
            sync_desktop=request.sync_desktop,
            sync_icons=request.sync_icons,
            sync_autostart=request.sync_autostart
        )
        
        success_count = sum(1 for success in results.values() if success)
        total_count = len(results)
        
        return success_response(
            data={"results": results},
            message=f"桌面同步完成，成功: {success_count}/{total_count}"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# API 路由 - 配置管理
# ============================================================================

@app.get("/api/config", response_model=ApiResponse, summary="获取配置")
async def get_config_settings(config: ConfigSettings = Depends(get_config)):
    """获取当前配置设置"""
    return success_response(
        data={"config": config.model_dump()},
        message="获取配置成功"
    )


@app.put("/api/config", response_model=ApiResponse, summary="更新配置")
async def update_config_settings(new_config: ConfigSettings):
    """更新配置设置"""
    try:
        # 这里可以实现配置持久化逻辑
        # 现在只是更新内存中的配置
        global config
        config = new_config
        
        return success_response(
            data={"config": config.model_dump()},
            message="配置更新成功"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# 错误处理
# ============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """HTTP异常处理"""
    return JSONResponse(
        status_code=exc.status_code,
        content=error_response(message=exc.detail).model_dump()
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """通用异常处理"""
    return JSONResponse(
        status_code=500,
        content=error_response(message=f"服务器内部错误: {str(exc)}").model_dump()
    )


# ============================================================================
# 启动事件
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """应用启动事件"""
    print(f"🚀 {TITLE} v{VERSION} 启动成功!")
    print(f"📝 API文档: http://localhost:8000/api/docs")
    print(f"🌐 Web界面: http://localhost:8000")
    
    # 检查依赖
    deps_ok, missing_deps = vnc_manager.check_dependencies()
    if not deps_ok:
        print(f"⚠️  警告: 缺少依赖 {missing_deps}")
    else:
        print("✅ 所有依赖检查通过")


@app.on_event("shutdown")
async def shutdown_event():
    """应用关闭事件"""
    print(f"🛑 {TITLE} 正在关闭...")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        reload_dirs=["app"],
        log_level="info"
    )