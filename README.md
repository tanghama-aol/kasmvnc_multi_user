# KasmVNC多用户管理系统

一个功能完整的KasmVNC多用户管理解决方案，提供bash脚本和Python Web界面两种使用方式。

## 🌟 主要功能

### 核心功能
- **批量用户创建**: 一键创建多个VNC用户，自动配置显示器和端口
- **服务管理**: 启动、停止、重启VNC服务，支持单用户和批量操作
- **桌面同步**: 将指定用户的桌面配置同步到其他用户
- **HTTPS支持**: 可选的SSL证书生成和HTTPS加密传输
- **系统监控**: 实时监控系统状态、资源使用情况和服务状态

### 特色功能
- **双显示器支持**: 每个用户默认配置两个虚拟显示器
- **音频支持**: 集成PulseAudio音频服务
- **Web管理界面**: 美观实用的Web管理界面
- **API接口**: 完整的RESTful API，支持二次开发
- **单文件部署**: 支持Nuitka打包为单个可执行文件

## 📋 系统要求

### 必要依赖
- Ubuntu/Debian Linux系统
- KasmVNC (`kasmvncserver`, `kasmvncpasswd`)
- OpenSSL (用于HTTPS证书生成)
- PulseAudio (音频支持)
- Python 3.8+ (仅Python版本需要)

### 推荐配置
- CPU: 4核心以上
- 内存: 8GB以上
- 磁盘: 100GB以上可用空间
- 网络: 千兆网络连接

## 🚀 快速开始

### 方式一：使用Bash脚本

1. **创建用户**
   ```bash
   # 创建5个用户，不启用HTTPS
   sudo ./scripts/create_user_with_vnc.sh 5
   
   # 创建3个用户，启用HTTPS
   sudo ./scripts/create_user_with_vnc.sh 3 --https
   ```

2. **管理服务**
   ```bash
   # 启动单个用户的VNC服务
   ./scripts/startkasmvnc.sh user1
   
   # 停止单个用户的VNC服务
   ./scripts/stopkasmvnc.sh user1
   
   # 启动所有用户的VNC服务
   ./scripts/start_allkasmvnc.sh
   
   # 停止所有用户的VNC服务
   ./scripts/stop_allkasmvnc.sh
   ```

3. **同步桌面**
   ```bash
   # 从tang用户同步桌面到所有用户
   ./scripts/sync_desktop.sh tang all
   
   # 模拟运行（不实际修改文件）
   ./scripts/sync_desktop.sh tang all --dry-run
   ```

### 方式二：使用Python Web界面

1. **安装依赖**
   ```bash
   cd python_app
   pip install -r requirements.txt
   ```

2. **启动Web服务**
   ```bash
   # 开发模式
   python run.py --reload
   
   # 生产模式
   python run.py --host 0.0.0.0 --port 8000
   ```

3. **访问Web界面**
   - Web界面: http://localhost:8000
   - API文档: http://localhost:8000/api/docs

4. **打包为单文件**
   ```bash
   # 安装Nuitka
   pip install nuitka
   
   # 打包应用
   python build.py
   
   # 运行打包后的程序
   ./dist/kasmvnc-manager --help
   ```

## 📚 详细文档

### 用户配置说明

每个用户会被创建如下配置：

| 用户 | 密码 | 主目录 | 显示器 | WebSocket端口 | VNC端口 |
|------|------|--------|--------|---------------|---------|
| user1 | zxt1000 | /home/share/user/user1 | :1010, :1020 | 4000, 4001 | 15901 |
| user2 | zxt2000 | /home/share/user/user2 | :1021, :1031 | 4002, 4003 | 15902 |
| user3 | zxt3000 | /home/share/user/user3 | :1032, :1042 | 4004, 4005 | 15903 |
| ... | ... | ... | ... | ... | ... |

### 目录结构

```
kasmvnc_multi_user/
├── scripts/                    # Bash脚本
│   ├── create_user_with_vnc.sh # 用户创建脚本
│   ├── startkasmvnc.sh        # 单用户启动脚本
│   ├── stopkasmvnc.sh         # 单用户停止脚本
│   ├── start_allkasmvnc.sh    # 批量启动脚本
│   ├── stop_allkasmvnc.sh     # 批量停止脚本
│   └── sync_desktop.sh        # 桌面同步脚本
├── python_app/                 # Python Web应用
│   ├── app/                    # 应用代码
│   │   ├── main.py            # FastAPI主应用
│   │   ├── models.py          # 数据模型
│   │   └── vnc_manager.py     # VNC管理器
│   ├── templates/              # HTML模板
│   ├── static/                 # 静态资源
│   ├── run.py                  # 启动脚本
│   ├── build.py                # 打包脚本
│   └── requirements.txt        # Python依赖
├── certs/                      # HTTPS证书目录
├── logs/                       # 日志目录
├── user_info.txt              # 用户信息汇总
└── README.md                   # 本文档
```

### API接口说明

#### 用户管理
- `POST /api/users/create` - 创建用户
- `GET /api/users` - 获取用户列表
- `GET /api/users/{username}` - 获取用户详情
- `DELETE /api/users/{username}` - 删除用户

#### 服务管理
- `POST /api/services/control` - 控制单个服务
- `POST /api/services/batch-control` - 批量控制服务

#### 系统监控
- `GET /api/status` - 获取系统状态
- `GET /api/info` - 获取服务信息
- `GET /api/logs` - 获取操作日志

#### 桌面同步
- `POST /api/desktop/sync` - 同步桌面配置

## 🔧 配置选项

### Bash脚本配置

可以通过修改脚本顶部的变量来调整配置：

```bash
# 用户主目录基路径
BASE_USER_HOME="/home/share/user"

# 基础显示器编号
BASE_DISPLAY=1010

# 基础端口号
BASE_PORT=15901

# VNC线程数
VNC_THREADS=4
```

### Python应用配置

可以通过环境变量或配置文件调整：

```python
# 基本配置
base_user_home = "/home/share/user"
cert_dir = "certs"
log_dir = "logs"
max_users = 50
vnc_threads = 4
default_resolution = "1920x1080"
enable_audio = True
```

## 🔐 安全注意事项

1. **权限管理**: 用户创建脚本需要root权限
2. **网络安全**: 建议在防火墙后使用，或启用HTTPS
3. **密码安全**: 默认密码较简单，建议修改
4. **证书管理**: HTTPS证书默认为自签名，生产环境建议使用正式证书

## 🐛 故障排除

### 常见问题

1. **VNC服务启动失败**
   - 检查端口是否被占用: `netstat -tlnp | grep :端口号`
   - 检查显示器锁文件: `ls /tmp/.X*-lock`
   - 查看详细日志: `tail -f logs/用户名_display_显示器号.log`

2. **用户创建失败**
   - 确认以root权限运行
   - 检查系统依赖是否安装完整
   - 查看脚本执行日志

3. **桌面同步不生效**
   - 检查源用户桌面目录是否存在
   - 确认目标用户有写权限
   - 重启VNC服务使配置生效

### 日志查看

```bash
# 查看系统日志
tail -f logs/vnc_manager.log

# 查看特定用户的VNC日志
tail -f logs/user1_display_1010.log

# 查看服务启动日志
journalctl -u your-service-name -f
```

## 🤝 贡献指南

欢迎提交Issue和Pull Request！

1. Fork本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启Pull Request

## 📄 许可证

本项目采用MIT许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 👨‍💻 作者

**Xander Xu** - [GitHub](https://github.com/XanderXu)

## 🙏 致谢

- [KasmVNC](https://kasmweb.com/) - 提供优秀的VNC解决方案
- [FastAPI](https://fastapi.tiangolo.com/) - 现代高性能的Python Web框架
- [Bootstrap](https://getbootstrap.com/) - 前端UI框架

---

如有问题或建议，请在[GitHub Issues](https://github.com/XanderXu/kasmvnc_multi_user/issues)中提出。