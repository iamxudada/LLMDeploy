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

set -e


export TMOUT=0
umask 022

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

UninstallSupiedtLmd() {
    docker ps -a -q | xargs docker rm -f
    docker network prune -f
    docker volume prune -f
    docker image prune -f
    rm -rf {{ lmdprojectpath }}
    echo -e "${GREEN}LMD uninstall success!${RESET}"
}

UninstallDriver() {
    if [ -d "/usr/local/Ascend/Ascend-Docker-Runtime" ]; then
        if [ -f "/usr/local/Ascend/Ascend-Docker-Runtime/script/uninstall.sh"]; then
            bash /usr/local/Ascend/Ascend-Docker-Runtime/script/uninstall.sh
        else
            rm -rf /usr/local/Ascend/Ascend-Docker-Runtime
        fi
    else
        echo -e "${YELLOW}Ascend-Docker-Runtime PATH not found!$ {RESET}"
    fi

    if [ -d "/usr/local/Ascend/firmware/" ]; then
        if [ -f "/usr/local/Ascend/firmware/script/uninstall.sh" ]; then
            bash /usr/local/Ascend/firmware/script/uninstall.sh
        else
            rm -rf /usr/local/Ascend/firmware
        fi
    else
        echo -e "${YELLOW}Firmware PATH not found!$ {RESET}"
    fi

    if [ -d "/usr/local/Ascend/driver" ]; then
        if [ -f "/usr/local/Ascend/driver/script/run_driver_uninstall.sh" ]; then
            bash /usr/local/Ascend/driver/script/run_driver_uninstall.sh
        else
            rm -rf /usr/local/Ascend/driver
        fi
    else
        echo -e "${YELLOW}Driver PATH not found!$ {RESET}"
    fi
}

UninstallDocker() {
    systemctl stop -f docker
    systemctl disable docker
    rm -rf /usr/lib/systemd/system/docker.service
    rm -rf /usr/lib/systemd/system/docker.socket
    rm -rf /usr/lib/systemd/system/containerd.service
    rm -rf /usr/bin/{containerd,containerd-shim,containerd-shim-runc-v2,docker-compose,docker-proxy,dockerd,docker,ctr,docker-init,runc}
    rm -rf /etc/docker
    rm -rf /data/Dependencies/docker
    groupdel -f docker
    echo -e "${GREEN}Docker uninstall success!${RESET}"
}

UninstallDenpendency() {
    data_blkid=$(blkid -s UUID -o value /dev/vg-lmd/data)
    sed -i "/$data_blkid/d" /etc/fstab
    sed -i "/{{ groups.master }}/d" /etc/hosts

    os_name=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
    case "$os_name" in
        "Ubuntu")
            system stop -f nfs-kernel-server
            apt-get remove --purge -y nfs-kernel-server nfs-common
            apt-get autoremove -y
            apt-get clean
            rm -rf /etc/apt/sources.list
            mv -f /etc/apt/sources.list.bak /etc/apt/sources.list
            ;;
        "EulerOS")
            systemctl stop -f rpcbind
            systemctl stop -f nfs-server
            dnf remove -y nfs-utils rpcbind
            dnf autoremove -y
            dnf clean
            rm -rf /etc/yum.repos.d/EulerOS.repo
            mv -f /etc/yum.repos.d/EulerOS.repo.bak /etc/yum.repos.d/EulerOS.repo
            ;;
        *)
            echo -e "${RED}Unsupported OS: $os_name ${RESET}"
            exit 1
            ;;
    esac

    rm -rf /data
    umount -l {{ lmdprojectpath }}/backend/BaseModels
    umount -l --force /data

    rm -rf /etc/security/limits.d/lmd.conf
    rm -rf /etc/sysctl.d/lmd.conf

    userdel -f HwHiAiUser

    # 拆散 lvm
    vgremove -ff lmd
    pvremove -ff /dev/vg-lmd/data
    rm -rf /dev/vg-lmd

    echo -e "${GREEN}Uninstall dependency success!${RESET}"

}

ClearMeta() {
    rm -rf /tmp/lmd
}


UninstallSupiedtLmd
UninstallDriver
UninstallDocker
UninstallDenpendency
ClearMeta
echo
echo -e "${GREEN}Uninstall all success!${RESET}"
echo