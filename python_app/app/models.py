#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KasmVNC多用户管理系统 - 数据模型
作者: Xander Xu
"""

from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from enum import Enum
import time


class ServiceStatus(str, Enum):
    """服务状态枚举"""
    RUNNING = "running"
    STOPPED = "stopped"
    ERROR = "error"
    UNKNOWN = "unknown"


class VNCDisplay(BaseModel):
    """VNC显示器信息"""
    display_number: int = Field(..., description="显示器编号")
    websocket_port: int = Field(..., description="WebSocket端口")
    status: ServiceStatus = Field(..., description="服务状态")
    pid: Optional[int] = Field(None, description="进程ID")
    log_file: Optional[str] = Field(None, description="日志文件路径")


class VNCUser(BaseModel):
    """VNC用户信息"""
    username: str = Field(..., description="用户名")
    password: str = Field(..., description="密码")
    home_directory: str = Field(..., description="主目录路径")
    displays: List[VNCDisplay] = Field([], description="显示器列表")
    https_enabled: bool = Field(False, description="是否启用HTTPS")
    cert_file: Optional[str] = Field(None, description="证书文件路径")
    key_file: Optional[str] = Field(None, description="密钥文件路径")
    created_time: float = Field(default_factory=time.time, description="创建时间")
    last_active: Optional[float] = Field(None, description="最后活跃时间")


class CreateUserRequest(BaseModel):
    """创建用户请求"""
    user_count: int = Field(..., ge=1, le=50, description="用户数量，1-50")
    enable_https: bool = Field(False, description="是否启用HTTPS")
    base_display: int = Field(1010, description="基础显示器编号")
    base_port: int = Field(15901, description="基础端口号")
    base_websocket_port: int = Field(4000, description="基础WebSocket端口")


class ServiceControlRequest(BaseModel):
    """服务控制请求"""
    username: str = Field(..., description="用户名")
    display_number: Optional[int] = Field(None, description="显示器编号，不指定则操作所有")
    action: str = Field(..., description="操作类型: start, stop, restart")


class DesktopSyncRequest(BaseModel):
    """桌面同步请求"""
    source_user: str = Field("tang", description="源用户名")
    target_users: List[str] = Field([], description="目标用户列表，空列表表示所有用户")
    sync_desktop: bool = Field(True, description="同步桌面文件")
    sync_icons: bool = Field(True, description="同步应用图标")
    sync_autostart: bool = Field(True, description="同步自启动应用")


class SystemStatus(BaseModel):
    """系统状态"""
    total_users: int = Field(..., description="总用户数")
    active_users: int = Field(..., description="活跃用户数")
    total_displays: int = Field(..., description="总显示器数")
    running_displays: int = Field(..., description="运行中显示器数")
    cpu_usage: float = Field(..., description="CPU使用率")
    memory_usage: float = Field(..., description="内存使用率")
    disk_usage: float = Field(..., description="磁盘使用率")
    uptime: float = Field(..., description="系统运行时间")


class ApiResponse(BaseModel):
    """API响应基类"""
    success: bool = Field(..., description="操作是否成功")
    message: str = Field(..., description="响应消息")
    data: Optional[Any] = Field(None, description="响应数据")
    timestamp: float = Field(default_factory=time.time, description="响应时间戳")


class OperationLog(BaseModel):
    """操作日志"""
    timestamp: float = Field(default_factory=time.time, description="时间戳")
    operation: str = Field(..., description="操作类型")
    username: Optional[str] = Field(None, description="相关用户")
    details: str = Field(..., description="操作详情")
    success: bool = Field(..., description="是否成功")
    error_message: Optional[str] = Field(None, description="错误信息")


class ConfigSettings(BaseModel):
    """配置设置"""
    base_user_home: str = Field("/home/share/user", description="用户主目录基路径")
    cert_dir: str = Field("certs", description="证书目录")
    log_dir: str = Field("logs", description="日志目录")
    max_users: int = Field(50, description="最大用户数量")
    vnc_threads: int = Field(4, description="VNC线程数")
    default_resolution: str = Field("1920x1080", description="默认分辨率")
    enable_audio: bool = Field(True, description="启用音频支持")
    auto_cleanup: bool = Field(True, description="自动清理")
    cleanup_interval: int = Field(3600, description="清理间隔（秒）")


class ServiceInfo(BaseModel):
    """服务信息"""
    service_name: str = Field(..., description="服务名称")
    version: str = Field(..., description="版本号")
    status: ServiceStatus = Field(..., description="服务状态")
    uptime: float = Field(..., description="运行时间")
    config: ConfigSettings = Field(..., description="配置信息")
    statistics: Dict[str, Any] = Field(..., description="统计信息")


class UserStatistics(BaseModel):
    """用户统计信息"""
    username: str = Field(..., description="用户名")
    total_sessions: int = Field(0, description="总会话数")
    active_time: float = Field(0, description="总活跃时间")
    last_login: Optional[float] = Field(None, description="最后登录时间")
    data_transferred: int = Field(0, description="数据传输量（字节）")
    display_count: int = Field(0, description="显示器数量")
    error_count: int = Field(0, description="错误计数")


class BatchOperationResult(BaseModel):
    """批量操作结果"""
    total_count: int = Field(..., description="总操作数")
    success_count: int = Field(..., description="成功数")
    failed_count: int = Field(..., description="失败数")
    results: List[Dict[str, Any]] = Field(..., description="详细结果")
    execution_time: float = Field(..., description="执行时间")


class NetworkInfo(BaseModel):
    """网络信息"""
    interface: str = Field(..., description="网络接口")
    ip_address: str = Field(..., description="IP地址")
    port_range: str = Field(..., description="端口范围")
    https_enabled: bool = Field(..., description="HTTPS状态")
    websocket_enabled: bool = Field(..., description="WebSocket状态")