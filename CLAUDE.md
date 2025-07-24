# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a KasmVNC multi-user system project that provides scripts and automation for creating and managing multiple VNC users with individual KasmVNC services. The project is designed to create isolated VNC environments for multiple users, each with their own display servers, ports, and optional HTTPS certificates.

## Development Goals

Based on the todo.list.md, the project aims to develop:

1. **User Creation Script**: `create_user_with_vnc.sh` - Creates N users (user1...userN) with:
   - Home directories at `/home/share/user/user1...userN`
   - Passwords following pattern `zxt1000...zxtN000`
   - Dual virtual displays per user (`:1010/:1020...101N/102N`)
   - Individual KasmVNC services starting at port 15901
   - Optional HTTPS certificate generation and configuration

2. **Service Management Scripts**:
   - Individual user control: `stopkasmvnc.sh user1`, `startkasmvnc.sh user1`
   - Bulk operations: `start_allkasmvnc.sh`, `stop_allkasmvnc.sh`

3. **Desktop Synchronization**: Script to copy tang user's desktop applications to all created users

## KasmVNC Configuration

The project uses KasmVNC with the following configuration pattern:
- XFCE desktop environment (`-select-de xfce`)
- 1920x1080 resolution with dual displays per user
- Configurable HTTPS support with certificate generation
- PulseAudio integration for audio support
- Multi-threaded rectangle processing

## File Structure

The repository currently contains:
- `README.md` - Basic project description (Chinese)
- `todo.list.md` - Development roadmap and specifications
- `LICENSE` - MIT License

## Development Context

This project is in early development phase with no existing implementation scripts. All development work should:
- Follow the specifications in `todo.list.md`
- Create shell scripts that handle multi-user VNC environments
- Implement proper user isolation and security
- Support both HTTP and HTTPS modes for KasmVNC
- Handle certificate generation for HTTPS mode
- Provide robust service management capabilities

## Security Considerations

When developing scripts for this project:
- Validate user input parameters
- Use secure password handling practices
- Properly set file permissions for user directories and certificates
- Implement safe user creation and deletion procedures
- Ensure VNC services are properly isolated between users

## 其他规则
1. 默认使用简体中文
2. 在开发新功能前，建立一个git版本，add 并 commit, 命名为"准备开发新功能名称，包含xx功能”，开发完成后，add, commit, push, 命名为"完成新功能名称，包含xx功能，并对开发进行总结"，加tag
3. 待开发功能，使用todo.list.md, 里面待开发的功能进行开发，将已完成的功能移到已开发中
4. 记录变更到changelog.md
5. 生成或修改中文的readme.md