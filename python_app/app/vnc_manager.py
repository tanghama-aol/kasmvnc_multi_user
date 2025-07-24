#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KasmVNC多用户管理系统 - VNC管理器
作者: Xander Xu
"""

import os
import subprocess
import psutil
import time
import json
import shutil
import tempfile
import signal
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import logging

from .models import (
    VNCUser, VNCDisplay, ServiceStatus, CreateUserRequest,
    ConfigSettings, SystemStatus, OperationLog
)


class VNCManager:
    """VNC服务管理器"""
    
    def __init__(self, config: ConfigSettings):
        self.config = config
        self.users_data_file = "users_data.json"
        self.operation_logs: List[OperationLog] = []
        self.setup_logging()
        self.ensure_directories()
    
    def setup_logging(self):
        """设置日志"""
        log_file = os.path.join(self.config.log_dir, "vnc_manager.log")
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file, encoding='utf-8'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def ensure_directories(self):
        """确保必要目录存在"""
        dirs = [
            self.config.base_user_home,
            self.config.cert_dir,
            self.config.log_dir
        ]
        for dir_path in dirs:
            os.makedirs(dir_path, exist_ok=True)
            self.logger.info(f"确保目录存在: {dir_path}")
    
    def log_operation(self, operation: str, username: str = None, 
                     details: str = "", success: bool = True, 
                     error_message: str = None):
        """记录操作日志"""
        log_entry = OperationLog(
            operation=operation,
            username=username,
            details=details,
            success=success,
            error_message=error_message
        )
        self.operation_logs.append(log_entry)
        
        # 限制日志数量
        if len(self.operation_logs) > 1000:
            self.operation_logs = self.operation_logs[-500:]
        
        # 记录到文件日志
        if success:
            self.logger.info(f"{operation}: {details}")
        else:
            self.logger.error(f"{operation} 失败: {error_message}")
    
    def save_users_data(self, users: List[VNCUser]):
        """保存用户数据到文件"""
        try:
            users_data = [user.model_dump() for user in users]
            with open(self.users_data_file, 'w', encoding='utf-8') as f:
                json.dump(users_data, f, ensure_ascii=False, indent=2)
            self.logger.info(f"用户数据已保存到 {self.users_data_file}")
        except Exception as e:
            self.logger.error(f"保存用户数据失败: {e}")
    
    def load_users_data(self) -> List[VNCUser]:
        """从文件加载用户数据"""
        try:
            if os.path.exists(self.users_data_file):
                with open(self.users_data_file, 'r', encoding='utf-8') as f:
                    users_data = json.load(f)
                users = [VNCUser(**user_data) for user_data in users_data]
                self.logger.info(f"已加载 {len(users)} 个用户数据")
                return users
        except Exception as e:
            self.logger.error(f"加载用户数据失败: {e}")
        return []
    
    def check_dependencies(self) -> Tuple[bool, List[str]]:
        """检查系统依赖"""
        dependencies = ["kasmvncserver", "kasmvncpasswd", "openssl", "pulseaudio"]
        missing = []
        
        for dep in dependencies:
            if not shutil.which(dep):
                missing.append(dep)
        
        if missing:
            self.log_operation("dependency_check", details=f"缺少依赖: {missing}", success=False)
        else:
            self.log_operation("dependency_check", details="依赖检查通过", success=True)
        
        return len(missing) == 0, missing
    
    def generate_ssl_certificate(self, username: str) -> Tuple[str, str]:
        """为用户生成SSL证书"""
        cert_file = os.path.join(self.config.cert_dir, f"{username}.crt")
        key_file = os.path.join(self.config.cert_dir, f"{username}.key")
        
        if os.path.exists(cert_file) and os.path.exists(key_file):
            self.logger.info(f"用户 {username} 的证书已存在")
            return cert_file, key_file
        
        try:
            # 生成自签名证书
            cmd = [
                "openssl", "req", "-x509", "-nodes", "-days", "365",
                "-newkey", "rsa:2048",
                "-keyout", key_file,
                "-out", cert_file,
                "-subj", f"/C=CN/ST=Beijing/L=Beijing/O=KasmVNC/OU=IT/CN={username}.kasmvnc.local"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                # 设置文件权限
                os.chmod(cert_file, 0o600)
                os.chmod(key_file, 0o600)
                
                self.log_operation("generate_certificate", username, 
                                 f"证书生成成功: {cert_file}, {key_file}")
                return cert_file, key_file
            else:
                raise Exception(f"OpenSSL 错误: {result.stderr}")
        
        except Exception as e:
            self.log_operation("generate_certificate", username, 
                             error_message=str(e), success=False)
            raise
    
    def create_system_user(self, username: str, password: str, home_dir: str) -> bool:
        """创建系统用户"""
        try:
            # 检查用户是否已存在
            try:
                subprocess.run(["id", username], check=True, capture_output=True)
                self.logger.info(f"用户 {username} 已存在")
                return True
            except subprocess.CalledProcessError:
                pass  # 用户不存在，继续创建
            
            # 创建用户目录
            os.makedirs(home_dir, exist_ok=True)
            
            # 创建用户
            cmd = ["useradd", "-m", "-d", home_dir, "-s", "/bin/bash", username]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                raise Exception(f"创建用户失败: {result.stderr}")
            
            # 设置密码
            cmd = ["chpasswd"]
            password_input = f"{username}:{password}"
            result = subprocess.run(cmd, input=password_input, text=True, capture_output=True)
            
            if result.returncode != 0:
                raise Exception(f"设置密码失败: {result.stderr}")
            
            # 设置目录权限
            shutil.chown(home_dir, username, username)
            os.chmod(home_dir, 0o755)
            
            # 创建VNC目录
            vnc_dir = os.path.join(home_dir, ".vnc")
            os.makedirs(vnc_dir, exist_ok=True)
            shutil.chown(vnc_dir, username, username)
            os.chmod(vnc_dir, 0o700)
            
            self.log_operation("create_user", username, f"系统用户创建成功: {home_dir}")
            return True
            
        except Exception as e:
            self.log_operation("create_user", username, error_message=str(e), success=False)
            return False
    
    def setup_vnc_password(self, username: str, password: str, home_dir: str) -> bool:
        """设置VNC密码"""
        try:
            vnc_dir = os.path.join(home_dir, ".vnc")
            passwd_file = os.path.join(vnc_dir, "passwd")
            
            if os.path.exists(passwd_file):
                self.logger.info(f"用户 {username} 的VNC密码已存在")
                return True
            
            # 设置VNC密码
            cmd = ["kasmvncpasswd", "-u", username, "-o", "-w", "-r"]
            password_input = f"{password}\\n{password}\\n"
            
            # 以用户身份执行
            result = subprocess.run(
                ["su", "-", username, "-c", f"echo -e '{password_input}' | kasmvncpasswd -u {username} -o -w -r"],
                capture_output=True, text=True, shell=True
            )
            
            if result.returncode != 0:
                raise Exception(f"设置VNC密码失败: {result.stderr}")
            
            self.log_operation("setup_vnc_password", username, "VNC密码设置成功")
            return True
            
        except Exception as e:
            self.log_operation("setup_vnc_password", username, error_message=str(e), success=False)
            return False
    
    def create_vnc_startup_script(self, username: str, display_num: int, 
                                 websocket_port: int, cert_file: str = None, 
                                 key_file: str = None) -> str:
        """创建VNC启动脚本"""
        home_dir = os.path.join(self.config.base_user_home, username)
        vnc_dir = os.path.join(home_dir, ".vnc")
        script_file = os.path.join(vnc_dir, f"start_display_{display_num}.sh")
        
        # 准备证书选项
        cert_opts = ""
        if cert_file and key_file:
            cert_opts = f"-cert {cert_file} -key {key_file}"
        
        # 生成启动脚本内容
        script_content = f"""#!/bin/bash
# KasmVNC启动脚本 - 用户: {username}, 显示器: :{display_num}
# 自动生成于: {time.strftime('%Y-%m-%d %H:%M:%S')}

USER={username}
DISPLAY_NUM={display_num}
WEBSOCKET_PORT={websocket_port}
VNC_THREADS={self.config.vnc_threads}

# 清理旧的显示器锁文件
rm -rf /tmp/.X${{DISPLAY_NUM}}-lock /tmp/.X11-unix/X${{DISPLAY_NUM}}

# 启动KasmVNC服务器
kasmvncserver :${{DISPLAY_NUM}} \\
    -select-de xfce \\
    -interface 0.0.0.0 \\
    -websocketPort ${{WEBSOCKET_PORT}} \\
    -geometry {self.config.default_resolution} \\
    -RectThreads ${{VNC_THREADS}} \\
    {cert_opts}

# 启动音频服务
if [ "{self.config.enable_audio}" = "True" ]; then
    pulseaudio --start --daemonize
fi

# 显示日志
tail -f ~/.vnc/*:${{DISPLAY_NUM}}.log
"""
        
        try:
            with open(script_file, 'w', encoding='utf-8') as f:
                f.write(script_content)
            
            # 设置权限
            os.chmod(script_file, 0o755)
            shutil.chown(script_file, username, username)
            
            self.log_operation("create_startup_script", username, 
                             f"启动脚本创建成功: {script_file}")
            return script_file
            
        except Exception as e:
            self.log_operation("create_startup_script", username, 
                             error_message=str(e), success=False)
            raise
    
    def create_xstartup_script(self, username: str) -> str:
        """创建Xstartup脚本"""
        home_dir = os.path.join(self.config.base_user_home, username)
        vnc_dir = os.path.join(home_dir, ".vnc")
        xstartup_file = os.path.join(vnc_dir, "xstartup")
        
        xstartup_content = """#!/bin/bash
# KasmVNC Xstartup脚本

# 设置环境变量
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export DESKTOP_SESSION=xfce

# 启动XFCE桌面环境
if [ -x /usr/bin/startxfce4 ]; then
    exec startxfce4
elif [ -x /usr/bin/xfce4-session ]; then
    exec xfce4-session
else
    # 备用桌面环境
    exec /usr/bin/x-window-manager
fi
"""
        
        try:
            with open(xstartup_file, 'w', encoding='utf-8') as f:
                f.write(xstartup_content)
            
            os.chmod(xstartup_file, 0o755)
            shutil.chown(xstartup_file, username, username)
            
            self.log_operation("create_xstartup_script", username, 
                             f"Xstartup脚本创建成功: {xstartup_file}")
            return xstartup_file
            
        except Exception as e:
            self.log_operation("create_xstartup_script", username, 
                             error_message=str(e), success=False)
            raise
    
    def create_users(self, request: CreateUserRequest) -> List[VNCUser]:
        """批量创建用户"""
        users = []
        
        # 检查依赖
        deps_ok, missing_deps = self.check_dependencies()
        if not deps_ok:
            raise Exception(f"缺少依赖: {missing_deps}")
        
        self.log_operation("create_users_batch", details=f"开始创建 {request.user_count} 个用户")
        
        for i in range(1, request.user_count + 1):
            try:
                username = f"user{i}"
                password = f"zxt{i}000"
                home_dir = os.path.join(self.config.base_user_home, username)
                
                # 创建系统用户
                if not self.create_system_user(username, password, home_dir):
                    continue
                
                # 设置VNC密码
                if not self.setup_vnc_password(username, password, home_dir):
                    continue
                
                # 生成证书
                cert_file, key_file = None, None
                if request.enable_https:
                    cert_file, key_file = self.generate_ssl_certificate(username)
                
                # 创建显示器配置
                displays = []
                for j in range(2):  # 每个用户两个显示器
                    display_num = request.base_display + (i - 1) * 10 + j * 10
                    websocket_port = request.base_websocket_port + (i - 1) * 2 + j
                    
                    # 创建启动脚本
                    self.create_vnc_startup_script(
                        username, display_num, websocket_port, cert_file, key_file
                    )
                    
                    display = VNCDisplay(
                        display_number=display_num,
                        websocket_port=websocket_port,
                        status=ServiceStatus.STOPPED
                    )
                    displays.append(display)
                
                # 创建Xstartup脚本
                self.create_xstartup_script(username)
                
                # 创建用户对象
                user = VNCUser(
                    username=username,
                    password=password,
                    home_directory=home_dir,
                    displays=displays,
                    https_enabled=request.enable_https,
                    cert_file=cert_file,
                    key_file=key_file
                )
                
                users.append(user)
                self.log_operation("create_user_complete", username, f"用户创建完成")
                
            except Exception as e:
                self.log_operation("create_user_complete", f"user{i}", 
                                 error_message=str(e), success=False)
                continue
        
        # 保存用户数据
        if users:
            self.save_users_data(users)
        
        self.log_operation("create_users_batch", 
                         details=f"批量创建完成，成功: {len(users)}/{request.user_count}")
        
        return users
    
    def get_process_by_display(self, display_num: int) -> Optional[psutil.Process]:
        """根据显示器编号获取进程"""
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    if proc.info['name'] == 'kasmvncserver':
                        cmdline = ' '.join(proc.info['cmdline'])
                        if f":{display_num}" in cmdline:
                            return proc
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception:
            pass
        return None
    
    def start_vnc_display(self, username: str, display_num: int) -> bool:
        """启动VNC显示器"""
        try:
            # 检查是否已经在运行
            if self.get_process_by_display(display_num):
                self.logger.info(f"显示器 :{display_num} 已在运行")
                return True
            
            home_dir = os.path.join(self.config.base_user_home, username)
            vnc_dir = os.path.join(home_dir, ".vnc")
            script_file = os.path.join(vnc_dir, f"start_display_{display_num}.sh")
            
            if not os.path.exists(script_file):
                raise Exception(f"启动脚本不存在: {script_file}")
            
            # 创建日志目录
            log_file = os.path.join(self.config.log_dir, f"{username}_display_{display_num}.log")
            
            # 以用户身份启动VNC服务
            cmd = ["su", "-", username, "-c", f"nohup bash '{script_file}' > '{log_file}' 2>&1 &"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                raise Exception(f"启动失败: {result.stderr}")
            
            # 等待启动
            time.sleep(3)
            
            # 验证启动状态
            proc = self.get_process_by_display(display_num)
            if proc:
                self.log_operation("start_vnc_display", username, 
                                 f"显示器 :{display_num} 启动成功 (PID: {proc.pid})")
                return True
            else:
                raise Exception("启动后未发现进程")
                
        except Exception as e:
            self.log_operation("start_vnc_display", username, 
                             error_message=str(e), success=False)
            return False
    
    def stop_vnc_display(self, username: str, display_num: int) -> bool:
        """停止VNC显示器"""
        try:
            proc = self.get_process_by_display(display_num)
            if not proc:
                self.logger.info(f"显示器 :{display_num} 未在运行")
                return True
            
            # 尝试优雅停止
            proc.terminate()
            
            # 等待进程停止
            try:
                proc.wait(timeout=10)
            except psutil.TimeoutExpired:
                # 强制停止
                self.logger.warning(f"优雅停止超时，强制停止进程 {proc.pid}")
                proc.kill()
                proc.wait(timeout=5)
            
            # 清理锁文件
            lock_files = [
                f"/tmp/.X{display_num}-lock",
                f"/tmp/.X11-unix/X{display_num}"
            ]
            for lock_file in lock_files:
                try:
                    if os.path.exists(lock_file):
                        os.remove(lock_file)
                except OSError:
                    pass
            
            self.log_operation("stop_vnc_display", username, 
                             f"显示器 :{display_num} 停止成功")
            return True
            
        except Exception as e:
            self.log_operation("stop_vnc_display", username, 
                             error_message=str(e), success=False)
            return False
    
    def get_system_status(self) -> SystemStatus:
        """获取系统状态"""
        try:
            users = self.load_users_data()
            
            # 统计用户和显示器
            total_users = len(users)
            active_users = 0
            total_displays = 0
            running_displays = 0
            
            for user in users:
                total_displays += len(user.displays)
                user_has_running = False
                
                for display in user.displays:
                    if self.get_process_by_display(display.display_number):
                        running_displays += 1
                        user_has_running = True
                
                if user_has_running:
                    active_users += 1
            
            # 系统资源信息
            cpu_usage = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            return SystemStatus(
                total_users=total_users,
                active_users=active_users,
                total_displays=total_displays,
                running_displays=running_displays,
                cpu_usage=cpu_usage,
                memory_usage=memory.percent,
                disk_usage=disk.percent,
                uptime=time.time() - psutil.boot_time()
            )
            
        except Exception as e:
            self.logger.error(f"获取系统状态失败: {e}")
            return SystemStatus(
                total_users=0,
                active_users=0,
                total_displays=0,
                running_displays=0,
                cpu_usage=0.0,
                memory_usage=0.0,
                disk_usage=0.0,
                uptime=0.0
            )
    
    def sync_desktop(self, source_user: str, target_users: List[str], 
                    sync_desktop: bool = True, sync_icons: bool = True, 
                    sync_autostart: bool = True) -> Dict[str, bool]:
        """同步桌面配置"""
        results = {}
        
        try:
            # 如果目标用户列表为空，获取所有用户
            if not target_users:
                users = self.load_users_data()
                target_users = [user.username for user in users]
            
            source_home = f"/home/{source_user}"
            
            for target_username in target_users:
                if target_username == source_user:
                    continue
                
                try:
                    target_home = os.path.join(self.config.base_user_home, target_username)
                    
                    # 同步桌面文件
                    if sync_desktop:
                        self._sync_desktop_files(source_home, target_home, target_username)
                    
                    # 同步图标
                    if sync_icons:
                        self._sync_icons(source_home, target_home, target_username)
                    
                    # 同步自启动
                    if sync_autostart:
                        self._sync_autostart(source_home, target_home, target_username)
                    
                    results[target_username] = True
                    self.log_operation("sync_desktop", target_username, 
                                     f"桌面同步成功 (源: {source_user})")
                    
                except Exception as e:
                    results[target_username] = False
                    self.log_operation("sync_desktop", target_username, 
                                     error_message=str(e), success=False)
            
        except Exception as e:
            self.log_operation("sync_desktop", details=f"桌面同步失败: {e}", success=False)
        
        return results
    
    def _sync_desktop_files(self, source_home: str, target_home: str, target_username: str):
        """同步桌面文件"""
        desktop_dirs = ["Desktop", "桌面"]
        
        for desktop_dir in desktop_dirs:
            source_desktop = os.path.join(source_home, desktop_dir)
            target_desktop = os.path.join(target_home, desktop_dir)
            
            if os.path.exists(source_desktop):
                os.makedirs(target_desktop, exist_ok=True)
                
                # 复制文件
                for root, dirs, files in os.walk(source_desktop):
                    for file in files:
                        if file.endswith(('.desktop', '.sh', '.png', '.jpg', '.jpeg', '.svg', '.ico')):
                            source_file = os.path.join(root, file)
                            rel_path = os.path.relpath(source_file, source_desktop)
                            target_file = os.path.join(target_desktop, rel_path)
                            
                            os.makedirs(os.path.dirname(target_file), exist_ok=True)
                            shutil.copy2(source_file, target_file)
                            
                            # 修复.desktop文件路径
                            if file.endswith('.desktop'):
                                self._fix_desktop_file(target_file, target_username)
                            
                            shutil.chown(target_file, target_username, target_username)
                
                shutil.chown(target_desktop, target_username, target_username)
    
    def _sync_icons(self, source_home: str, target_home: str, target_username: str):
        """同步图标"""
        source_icons = os.path.join(source_home, ".local/share/icons")
        target_icons = os.path.join(target_home, ".local/share/icons")
        
        if os.path.exists(source_icons):
            os.makedirs(os.path.dirname(target_icons), exist_ok=True)
            shutil.copytree(source_icons, target_icons, dirs_exist_ok=True)
            shutil.chown(target_icons, target_username, target_username)
    
    def _sync_autostart(self, source_home: str, target_home: str, target_username: str):
        """同步自启动应用"""
        source_autostart = os.path.join(source_home, ".config/autostart")
        target_autostart = os.path.join(target_home, ".config/autostart")
        
        if os.path.exists(source_autostart):
            os.makedirs(target_autostart, exist_ok=True)
            
            for file in os.listdir(source_autostart):
                if file.endswith('.desktop'):
                    source_file = os.path.join(source_autostart, file)
                    target_file = os.path.join(target_autostart, file)
                    
                    shutil.copy2(source_file, target_file)
                    self._fix_desktop_file(target_file, target_username)
                    shutil.chown(target_file, target_username, target_username)
            
            shutil.chown(target_autostart, target_username, target_username)
    
    def _fix_desktop_file(self, desktop_file: str, target_username: str):
        """修复desktop文件中的路径"""
        try:
            with open(desktop_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            target_home = os.path.join(self.config.base_user_home, target_username)
            
            # 替换路径
            content = content.replace(f"/home/tang", target_home)  # 假设源用户是tang
            
            with open(desktop_file, 'w', encoding='utf-8') as f:
                f.write(content)
                
        except Exception as e:
            self.logger.error(f"修复desktop文件失败 {desktop_file}: {e}")
    
    def get_operation_logs(self, limit: int = 100) -> List[OperationLog]:
        """获取操作日志"""
        return self.operation_logs[-limit:] if self.operation_logs else []