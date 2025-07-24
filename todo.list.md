## 待开发

### 1. 使用bash脚本实现添加用户和创建此用户的kasmvnc服务 
1. 编写多用户kasmvnc多用户系统创建脚本： create_user_with_vnc.sh 用户数量N
   
   生成user1...userN用户，用户主目录为/home/share/user/user1...userN,密码为zxt1000...zxtN000
给每个用户创建自己的display，分辨率为1920x1080, 每个用户两个虚拟显示器，display分别为:1010/1020...101N/102N
给每个用户创建自己的kasmvnc服务，端口为15901开始递增，可用通过参数给出是否启用https，如果启用，则需要生成此用户的https证书HTTPS_CERT和HTTPS_CERT_KEY，并添加HTTPS_CERT和HTTPS_CERT_KEY到环境变量中
kasmvnc启动脚本示例如下：
```
#!/bin/sh
# set password for kasmvnc
if [ ! -f "/home/$USER/.vnc/passwd" ]; then
    su $USER -c "echo -e \"$PASSWORD\n$PASSWORD\n\" | kasmvncpasswd -u $USER -o -w -r"
fi
rm -rf /tmp/.X1000-lock /tmp/.X11-unix/X1000
# start kasmvnc
su $USER -c "kasmvncserver :1000 -select-de xfce -interface 0.0.0.0 -websocketPort 4000 -cert $HTTPS_CERT -key $HTTPS_CERT_KEY -RectThreads $VNC_THREADS"
su $USER -c "pulseaudio --start"
tail -f /home/$USER/.vnc/*.log
```

2. 生成启动关闭各用户kasmvnc服务的脚本：
单个用户的启停脚本：
stopkasmvnc.sh user1 
startkasmvnc.sh user1

多个用户的启停脚本：
start_allkasmvnc.sh
stop_allkasmvnc.sh

3. 开发桌面同步脚本，将tang桌面应用拷贝到各个用户自己的桌面

### 2. python实现
将上述功能集中在python代码中，此时不需要引用脚本，全部功能由python实现，并提供fastapi的web界面，要求界面美观实用易于理解操作，最好不要引用复杂的web框架，只使用html/js/css, 如果需要使用cdn的外部组件，需要支持其资源下载到本地目录中，包括css,js,字体，图片等
提供nuitka打包脚本，将python打包成单文件脚本，包含所有资源