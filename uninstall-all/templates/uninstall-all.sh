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

# Color definitions
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
}

# Helper function to safely remove files/directories
safe_remove() {
    local path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path" || log_warn "Failed to remove: $path"
    fi
}

# Helper function to run uninstall scripts
run_uninstall_script() {
    local script_path="$1"
    local component="$2"
    if [ -f "$script_path" ]; then
        log_info "Uninstalling $component..."
        bash "$script_path" || log_warn "Failed to run uninstall script for $component"
    else
        log_warn "$component uninstall script not found, removing directory"
        safe_remove "$(dirname "$script_path")"
    fi
}

UninstallSupiedtLmd() {
    log_info "Uninstalling LMD components..."
    docker ps -a -q | xargs -r docker rm -f 2>/dev/null || log_warn "Failed to remove some containers"
    docker network prune -f || log_warn "Failed to prune networks"
    docker volume prune -f || log_warn "Failed to prune volumes"
    docker image prune -f || log_warn "Failed to prune images"
    safe_remove "{{ lmdprojectpath }}"
    log_info "LMD uninstall completed"
}

UninstallDriver() {
    log_info "Uninstalling drivers..."
    
    # Ascend Docker Runtime
    run_uninstall_script "/usr/local/Ascend/Ascend-Docker-Runtime/script/uninstall.sh" "Ascend-Docker-Runtime"
    
    # Firmware
    run_uninstall_script "/usr/local/Ascend/firmware/script/uninstall.sh" "Firmware"
    
    # Driver
    run_uninstall_script "/usr/local/Ascend/driver/script/run_driver_uninstall.sh" "Driver"
    
    log_info "Driver uninstall completed"
}

UninstallDocker() {
    log_info "Uninstalling Docker..."
    
    # Stop and disable services
    systemctl stop docker || log_warn "Failed to stop docker service"
    systemctl disable docker || log_warn "Failed to disable docker service"
    
    # Remove systemd files
    local systemd_files=(
        "/usr/lib/systemd/system/docker.service"
        "/usr/lib/systemd/system/docker.socket"
        "/usr/lib/systemd/system/containerd.service"
    )
    for file in "${systemd_files[@]}"; do
        safe_remove "$file"
    done
    
    # Remove binaries
    local binaries=(
        "containerd" "containerd-shim" "containerd-shim-runc-v2"
        "docker-compose" "docker-proxy" "dockerd" "docker"
        "ctr" "docker-init" "runc"
    )
    for bin in "${binaries[@]}"; do
        safe_remove "/usr/bin/$bin"
    done
    
    # Remove directories
    safe_remove "/etc/docker"
    safe_remove "/data/Dependencies/docker"
    
    # Remove docker group
    groupdel -f docker 2>/dev/null || log_warn "Failed to remove docker group"
    
    log_info "Docker uninstall completed"
}

UninstallDependency() {
    log_info "Uninstalling dependencies..."
    
    # Update fstab
    local data_blkid
    data_blkid=$(blkid -s UUID -o value /dev/vg-lmd/data) || log_warn "Failed to get UUID for /dev/vg-lmd/data"
    if [ -n "$data_blkid" ]; then
        sed -i "/$data_blkid/d" /etc/fstab
    fi
    sed -i "/{{ groups.master }}/d" /etc/hosts
    
    # OS-specific package removal
    local os_name
    os_name=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
    case "$os_name" in
        "Ubuntu")
            systemctl stop nfs-kernel-server || log_warn "Failed to stop NFS server"
            apt-get remove --purge -y nfs-kernel-server nfs-common || log_warn "Failed to remove NFS packages"
            apt-get autoremove -y
            apt-get clean
            if [ -f "/etc/apt/sources.list.bak" ]; then
                mv -f /etc/apt/sources.list.bak /etc/apt/sources.list
            fi
            ;;
        "EulerOS")
            systemctl stop rpcbind nfs-server || log_warn "Failed to stop NFS services"
            dnf remove -y nfs-utils rpcbind || log_warn "Failed to remove NFS packages"
            dnf autoremove -y
            dnf clean all
            if [ -f "/etc/yum.repos.d/EulerOS.repo.bak" ]; then
                mv -f /etc/yum.repos.d/EulerOS.repo.bak /etc/yum.repos.d/EulerOS.repo
            fi
            ;;
        *)
            log_error "Unsupported OS: $os_name"
            exit 1
            ;;
    esac
    
    # Unmount and remove directories
    umount -l "{{ lmdprojectpath }}/backend/BaseModels" 2>/dev/null || log_warn "Failed to unmount BaseModels"
    umount -l --force /data 2>/dev/null || log_warn "Failed to unmount /data"
    safe_remove "/data"
    
    # Remove configuration files
    safe_remove "/etc/security/limits.d/lmd.conf"
    safe_remove "/etc/sysctl.d/lmd.conf"
    
    # Remove user
    userdel -f HwHiAiUser 2>/dev/null || log_warn "Failed to remove HwHiAiUser"
    
    # Remove LVM
    vgremove -ff lmd 2>/dev/null || log_warn "Failed to remove volume group"
    pvremove -ff /dev/vg-lmd/data 2>/dev/null || log_warn "Failed to remove physical volume"
    safe_remove "/dev/vg-lmd"
    
    log_info "Dependency uninstall completed"
}

ClearMeta() {
    log_info "Clearing metadata..."
    safe_remove "/tmp/lmd"
    log_info "Metadata cleared"
}

# Main execution
main() {
    log_info "Starting uninstallation process..."
    
    UninstallSupiedtLmd
    UninstallDriver
    UninstallDocker
    UninstallDependency
    ClearMeta
    
    echo
    log_info "All components uninstalled successfully"
    echo
}

main