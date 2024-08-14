#!/usr/bin/env bash

# Copyright (c) 2024-08-01 xulinchun <xulinchun0806@outlook.com>
#
# This file is part of LMD.
#
# LMD is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2.1 of the License, or
# (at your option) any later version.
#
# LMD is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with LMD.  If not, see <http://www.gnu.org/licenses/>.
#==============================================================================

export TMOUT=0
umask 022

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# 获取架构类型
os_name=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
os_version=$(awk -F '=' '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
os_architecture=$(uname -m)

case "$os_name $os_version" in
    "Ubuntu 18.04")
        mv -f /etc/apt/sources.list /etc/apt/sources.list.bak
        cp /tmp/lmd/repo/Ubuntu-18.04.repo /etc/apt/sources.list
        apt-get update
        apt-get install -y curl wget git pciutils gcc g++ make unzip zip dkms kernel-headers-$(uname -r)
        # 锁定内核版本
        apt-mark hold linux-image-$(uname -r) linux-header-$(uname -r)
        apt-mark showhold
        # 如果有子节点则安装 nfs
        if [ -z "{{ groups.workers }}" ]; then
            apt-get install -y nfs-kernel-server nfs-common
            systemctl enable nfs-kernel-server.service --now
            install_nfs="true"
        fi
        ;;
    "Ubuntu 20.04")
        mv -f /etc/apt/sources.list /etc/apt/sources.list.bak
        cp /tmp/lmd/repo/Ubuntu-20.04.repo /etc/apt/sources.list
        apt-get update
        apt-get install -y curl wget git pciutils gcc g++ make unzip zip dkms kernel-headers-$(uname -r)
        # 锁定内核版本
        apt-mark hold linux-image-$(uname -r) linux-header-$(uname -r)
        apt-mark showhold
        # 如果有子节点则安装 nfs
        if [ -z "{{ groups.workers }}" ]; then
            apt-get install -y nfs-kernel-server nfs-common
            systemctl enable nfs-kernel-server.service --now
            install_nfs="true"
        fi
        ;;
    "EulerOS 2.0")
        mv -f /etc/yum.repos.d/EulerOS.repo /etc/yum.repos.d/EulerOS.repo.bak
        cp /tmp/lmd/repo/EulerOS.repo /etc/yum.repos.d/EulerOS.repo
        dnf makecache
        dnf install -y curl wget git pciutils gcc g++ make unzip zip dkms kernel-headers-$(uname -r) kernel-devel-$(uname -r) python3-dnf-plugin-versionlock
        # 锁定内核版本
        dnf versionlock add kernel-$(uname -r) kernel-headers-$(uname -r)
        dnf versionlock list

        # 如果有子节点则安装 nfs
        if [ -z "{{ groups.workers }}" ]; then
            dnf install -y nfs-utils rpcbind
            systemctl enable rpcbind.service --now
            systemctl enable nfs-server.service --now
            install_nfs="true"
        fi
        ;;
    *)
        echo -e "${RED}Unsupported OS: $os_name $os_version $os_architecture ${RESET}"
        exit 1
        ;;
esac

# 创建用户
if [ ! -d "/home/HwHiAiUser" ]; then
    useradd -d /home/HwHiAiUser -m -s /usr/sbin/nologin HwHiAiUser
fi

# 设置 sysctl 参数
cat << EOF > /etc/sysctl.d/lmd.conf
vm.dirty_background_ratio = 5                    # lmd
vm.dirty_ratio = 10                              # lmd
kernel.sched_autogroup_enabled = 0               # lmd
net.ipv4.ip_forward = 1                          # lmd
net.ipv4.conf.all.send_redirects = 0             # lmd
net.ipv4.conf.default.send_redirects = 0         # lmd
net.ipv4.conf.all.accept_source_route = 0        # lmd
net.ipv4.conf.default.accept_source_route = 0    # lmd
net.ipv4.conf.all.accept_redirects = 0           # lmd
net.ipv4.conf.default.accept_redirects = 0       # lmd
net.ipv4.conf.all.secure_redirects = 0           # lmd
net.ipv4.conf.default.secure_redirects = 0       # lmd
net.ipv4.icmp_echo_ignore_broadcasts = 1         # lmd
net.ipv4.icmp_ignore_bogus_error_responses = 1   # lmd
net.ipv4.conf.all.rp_filter = 1                  # lmd
net.ipv4.conf.default.rp_filter = 1              # lmd
net.ipv4.tcp_syncookies = 1                      # lmd
net.ipv4.tcp_tw_reuse = 1                        # lmd
kernel.dmesg_restrict = 0                        # lmd
net.ipv6.conf.all.accept_redirects = 0           # lmd
net.ipv6.conf.default.accept_redirects = 0       # lmd
net.ipv4.icmp_echo_ignore_broadcasts = 1         # lmd
kernel.sysrq = 1                                 # lmd
vm.swappiness = 0                                # lmd
net.core.somaxconn = 4096                        # lmd
net.ipv4.tcp_max_tw_buckets = 5000               # lmd
net.ipv4.tcp_max_syn_backlog = 4096              # lmd
fs.file-max = 655350                             # lmd
EOF
sysctl -p


# 设置文件句柄限制
ulimit -n 655350
cat << EOF > /etc/security/limits.d/lmd.conf
# lmd
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
EOF

# 配置 lvm
if [ {{ is_createdatalvm }} == "true" ]; then

    getPVdisplayName=$(pvdisplay | grep "PV Name" | awk '{ print $3}' | paste -sd' ' -)
    if [ "${getPVdisplayName}" != "{{ lvm_compositiondisks }}" ]; then
        for i in {{ lvm_compositiondisks }}; do
            pvcreate $i
        done
    fi

    getVGdisplayName=$(vgdisplay | grep "VG Name" | awk '{ print $3}' | paste -sd' ' -)
    if [ "${getVGdisplayName}" != "vg-lmd" ]; then
        vgcreate vg-lmd {{ lvm_compositiondisks }}
        lvcreate -l 100%FREE -n data vg-lmd
    fi

    if [ $(lsblk -o FSTYPE /dev/vg-lmd/data | tail -1) != "ext4" ]; then
        mkfs.ext4 -F /dev/vg-lmd/data
    fi
    if [ ! -d "/data" ]; then
        mkdir /data
    else
        rm -rf /data/*
    fi
    data_blkid=$(blkid -s UUID -o value /dev/vg-lmd/data)
    if [ $(grep $data_blkid /etc/fstab) == "" ]; then
        echo "UUID=$data_blkid /data ext4 defaults 0 0" >> /etc/fstab
    fi
    mount -a

    if [ -z "{{ groups.workers }}" ] && [ "{{ groups.master }}" == "$(hostname -I | awk '{print $1}')"]; then
        mkdir -p /data/applications/lmd/backend/BaseModels
        if [ !-f "/etc/exports.d/lmd.conf" ]; then
            echo "/data/applications/lmd/backend/BaseModels *(rw,async,no_root_squash,no_subtree_check,insecure)" > /etc/exports.d/lmd.conf
        fi
        exportfs -avf
    fi

    if [ -z "{{ groups.workers }}" ] && [ "{{ groups.workers }}" == "$(hostname -I | awk '{print $1}')"]; then
        mkdir -p /data/applications/lmd/backend/BaseModels
        if [ "grep /data/applications/lmd/backend/BaseModels /etc/fstab" == "" ]; then
            echo "{{ groups.master }}:/data/applications/lmd/backend/BaseModels /data/applications/lmd/backend/BaseModels" >> /etc/fstab
        fi
        mount -a
    fi
fi
