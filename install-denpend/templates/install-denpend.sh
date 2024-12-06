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

log_info() {
    printf "${GREEN}[INFO]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
}

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Command not found: $1"
        return 1
    fi
}

check_dir() {
    if [ ! -d "$1" ]; then
        log_info "Creating directory: $1"
        mkdir -p "$1" || {
            log_error "Failed to create directory: $1"
            return 1
        }
    fi
}

install_packages() {
    local packages=("$@")
    log_info "Installing packages: ${packages[*]}"
    
    if command -v apt-get &>/dev/null; then
        apt-get update || {
            log_error "Failed to update package list"
            return 1
        }
        apt-get install -y "${packages[@]}" || {
            log_error "Failed to install packages: ${packages[*]}"
            return 1
        }
    elif command -v dnf &>/dev/null; then
        dnf makecache || {
            log_error "Failed to update package cache"
            return 1
        }
        dnf install -y "${packages[@]}" || {
            log_error "Failed to install packages: ${packages[*]}"
            return 1
        }
    else
        log_error "No supported package manager found"
        return 1
    fi
}

readonly OS_NAME=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
readonly OS_VERSION=$(awk -F '=' '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"' | awk '{$1=$1};1')
readonly OS_ARCH=$(uname -m)
readonly KERNEL_VERSION=$(uname -r)
readonly CURRENT_IP=$(hostname -I | awk '{print $1}')

setup_os_dependencies() {
    case "${OS_NAME} ${OS_VERSION}" in
        "Ubuntu 18.04"|"Ubuntu 20.04")
            log_info "Setting up Ubuntu ${OS_VERSION} dependencies..."
            cp /etc/apt/sources.list /etc/apt/sources.list.bak || log_warn "Failed to backup sources.list"
            cp "/tmp/lmd/repo/Ubuntu-${OS_VERSION}.repo" /etc/apt/sources.list || {
                log_error "Failed to copy repository file"
                return 1
            }
            
            install_packages curl wget git pciutils gcc g++ make unzip zip dkms "kernel-headers-${KERNEL_VERSION}"
            
            apt-mark hold "linux-image-${KERNEL_VERSION}" "linux-header-${KERNEL_VERSION}" || log_warn "Failed to hold kernel packages"
            apt-mark showhold
            
            if [ -z "{{ groups.workers }}" ]; then
                install_packages nfs-kernel-server nfs-common
                systemctl enable nfs-kernel-server.service --now || log_warn "Failed to enable NFS server"
            fi
            ;;
            
        "EulerOS 2.0")
            log_info "Setting up EulerOS dependencies..."
            cp /etc/yum.repos.d/EulerOS.repo /etc/yum.repos.d/EulerOS.repo.bak || log_warn "Failed to backup EulerOS.repo"
            cp /tmp/lmd/repo/EulerOS.repo /etc/yum.repos.d/EulerOS.repo || {
                log_error "Failed to copy repository file"
                return 1
            }
            
            install_packages curl wget git pciutils gcc g++ make unzip zip dkms \
                "kernel-headers-${KERNEL_VERSION}" "kernel-devel-${KERNEL_VERSION}" python3-dnf-plugin-versionlock
            
            dnf versionlock add "kernel-${KERNEL_VERSION}" "kernel-headers-${KERNEL_VERSION}" || log_warn "Failed to lock kernel version"
            dnf versionlock list
            
            if [ -z "{{ groups.workers }}" ]; then
                install_packages nfs-utils rpcbind
                systemctl enable rpcbind.service --now || log_warn "Failed to enable rpcbind"
                systemctl enable nfs-server.service --now || log_warn "Failed to enable NFS server"
            fi
            ;;
            
        *)
            log_error "Unsupported OS: ${OS_NAME} ${OS_VERSION} ${OS_ARCH}"
            return 1
            ;;
    esac
}

create_user() {
    local username="$1"
    local home_dir="$2"
    
    if ! id -u "${username}" &>/dev/null; then
        log_info "Creating user: ${username}"
        useradd -d "${home_dir}" -m -s /usr/sbin/nologin "${username}" || {
            log_error "Failed to create user: ${username}"
            return 1
        }
    else
        log_info "User ${username} already exists"
    fi
}

set_sysctl_params() {
    log_info "Setting system parameters..."
    cat > /etc/sysctl.d/lmd.conf << 'EOF'
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
kernel.sched_autogroup_enabled = 0
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
kernel.dmesg_restrict = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.sysrq = 1
vm.swappiness = 0
net.core.somaxconn = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_syn_backlog = 4096
fs.file-max = 655350
EOF
    sysctl -p || log_warn "Failed to apply sysctl parameters"
}

set_file_limits() {
    log_info "Setting file limits..."
    ulimit -n 655350
    cat > /etc/security/limits.d/lmd.conf << 'EOF'
# lmd
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
EOF
}

configure_lvm() {
    if [ "{{ is_createdatalvm }}" != "true" ]; then
        log_info "Skipping LVM configuration"
        return 0
    fi
    
    log_info "Configuring LVM..."

    local current_pvs=$(pvdisplay | grep "PV Name" | awk '{ print $3}' | paste -sd' ' -)
    if [ "${current_pvs}" != "{{ lvm_compositiondisks }}" ]; then
        for disk in {{ lvm_compositiondisks }}; do
            log_info "Creating PV: ${disk}"
            pvcreate "${disk}" || {
                log_error "Failed to create PV: ${disk}"
                return 1
            }
        done
    fi

    local current_vg=$(vgdisplay | grep "VG Name" | awk '{ print $3}' | paste -sd' ' -)
    if [ "${current_vg}" != "vg-lmd" ]; then
        log_info "Creating VG: vg-lmd"
        vgcreate vg-lmd {{ lvm_compositiondisks }} || {
            log_error "Failed to create VG: vg-lmd"
            return 1
        }
        lvcreate -l 100%FREE -n data vg-lmd || {
            log_error "Failed to create LV: data"
            return 1
        }
    fi

    if [ "$(lsblk -no FSTYPE /dev/vg-lmd/data)" != "ext4" ]; then
        log_info "Formatting /dev/vg-lmd/data with ext4"
        mkfs.ext4 -F /dev/vg-lmd/data || {
            log_error "Failed to format /dev/vg-lmd/data"
            return 1
        }
    fi

    check_dir "/data"
    rm -rf /data/* || log_warn "Failed to clean /data directory"

    local data_uuid=$(blkid -s UUID -o value /dev/vg-lmd/data)
    if ! grep -q "${data_uuid}" /etc/fstab; then
        echo "UUID=${data_uuid} /data ext4 defaults 0 0" >> /etc/fstab || {
            log_error "Failed to update fstab"
            return 1
        }
    fi
    
    mount -a || {
        log_error "Failed to mount all filesystems"
        return 1
    }

    if [ -z "{{ groups.workers }}" ] && [ "${CURRENT_IP}" = "{{ groups.master }}" ]; then
        check_dir "{{ lmdprojectpath }}/backend/BaseModels"
        mkdir -p /etc/exports.d
        echo "{{ lmdprojectpath }}/backend/BaseModels *(rw,async,no_root_squash,no_subtree_check,insecure)" > /etc/exports.d/lmd.conf
        exportfs -avf || log_warn "Failed to export NFS share"
    fi

    if [ -n "{{ groups.workers }}" ] && [ "${CURRENT_IP}" = "{{ groups.workers }}" ]; then
        check_dir "{{ lmdprojectpath }}/backend/BaseModels"
        if ! grep -q "{{ lmdprojectpath }}/backend/BaseModels" /etc/fstab; then
            echo "{{ groups.master }}:{{ lmdprojectpath }}/backend/BaseModels {{ lmdprojectpath }}/backend/BaseModels nfs defaults 0 0" >> /etc/fstab
        fi
        mount -a || log_warn "Failed to mount NFS share"
    fi
}

main() {
    log_info "Starting dependency installation..."
    
    setup_os_dependencies
    create_user "HwHiAiUser" "/home/HwHiAiUser"
    set_sysctl_params
    set_file_limits
    configure_lvm
    
    log_info "Dependency installation completed"
}

main
