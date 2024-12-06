# LMDeploy

LMDeploy 是一个基于 Ansible 的大模型部署工具，用于自动化部署和管理大型 AI 模型。该工具提供了完整的环境配置、依赖安装、Docker 管理以及驱动程序安装等功能。

## 项目架构

### 主机组织结构


```ini
[master]          # 主节点组
└── 控制节点

[workers]         # 工作节点组
└── 计算节点

[lmd:children]    # LMD 节点组
├── master       # 包含主节点
└── workers      # 包含工作节点
```

## 功能特性

- **自动化部署**：通过 Ansible 实现全自动化部署
- **模块化设计**：采用 Ansible Role 架构，实现功能模块化
- **灵活配置**：支持多节点部署和自定义配置
- **完整流程**：覆盖从环境准备到服务启动的全流程
- **易于维护**：统一的配置管理和维护方式

## 系统要求

### 硬件要求
- CPU: 建议 8 核以上
- 内存: 最少 16GB
- 磁盘空间: 建议 100GB 以上
- 网络: 所有节点间需要网络互通

### 软件要求
- 操作系统: EulerOS / Ubuntu 18.04+
- Python: 3.6+
- Ansible: 2.9+
- SSH: 需要启用 SSH 服务

## 快速开始

### 1. 配置主机清单
编辑 `inventory` 文件，配置目标主机信息：
```ini
[master]
192.168.182.110 ansible_user=root ansible_port=22

[workers]
192.168.182.111
192.168.182.112
```

### 2. 配置环境变量
在 `inventory` 文件中设置必要的变量：
```ini
[lmd:vars]
lmdprojectpath=/data/applications/lmd     # LMD 项目路径
is_createdatalvm=false                    # 是否创建数据 LVM
lvm_compositiondisks="/dev/sdb /dev/sdc"  # 数据 LVM 磁盘组合
```

### 3. 执行部署
```bash
# 安装全部组件
./lmd install

# 卸载
./lmd uninstall

# 清理执行节点的相关包
./lmd clean
```

## 角色说明

### install-denpend
- 系统依赖包安装
- 基础环境配置
- 系统参数优化

### install-docker
- Docker 环境安装
- Docker 配置优化
- Docker Compose 安装

### install-driver
- 硬件驱动安装
- 驱动配置优化
- 驱动环境检查

### install-lmd
- LMD 服务安装
- 服务配置
- 启动脚本

### uninstall-all
- 组件卸载
- 环境清理
- 配置还原

## 常见问题

1. **安装失败排查**
   - 检查网络连接
   - 验证主机清单配置
   - 查看日志文件

2. **权限问题**
   - 确保 SSH 密钥配置正确
   - 检查目标主机权限
   - 验证 sudo 权限

## 维护者

xulinchun <xulinchun0806@outlook.com>

## 许可证

本项目采用 GNU 通用公共许可证 v2.1 授权 - 详见 LICENSE 文件。