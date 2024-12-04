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

download() {
    local url="$1"
    local path="$2"
    local max_retries=10
    local retry_delay=10
    local attempt=1

    log_info "Downloading: $(basename "${url}")"
    
    while [ $attempt -le $max_retries ]; do
        if curl -fsSL --connect-timeout 30 --retry 3 -o "${path}" "${url}"; then
            log_info "Download successful: $(basename "${path}")"
            return 0
        fi
        
        log_warn "Download attempt ${attempt} of ${max_retries} failed. Retrying in ${retry_delay} seconds..."
        sleep "${retry_delay}"
        ((attempt++))
    done

    log_error "Failed to download after ${max_retries} attempts: $(basename "${url}")"
    return 1
}

copy_with_permissions() {
    local source_path="$1"
    local destination_path="$2"
    local mode="$3"
    
    if [ ! -e "${source_path}" ]; then
        log_error "Source file not found: ${source_path}"
        return 1
    fi
    
    local dest_dir
    dest_dir=$(dirname "${destination_path}")
    check_dir "${dest_dir}" || return 1
    
    if ! cp -a "${source_path}" "${destination_path}"; then
        log_error "Failed to copy: ${source_path} -> ${destination_path}"
        return 1
    fi
    
    if ! chmod "${mode}" "${destination_path}"; then
        log_error "Failed to set permissions ${mode} on: ${destination_path}"
        return 1
    fi
    
    log_info "Copied with permissions ${mode}: ${destination_path}"
    return 0
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "/tmp/lmd/docker" "/tmp/lmd/${DockerName}" "/tmp/lmd/${DockerComposeName}"
}

trap cleanup EXIT

setup_urls() {
    local arch
    arch=$(uname -m)
    
    case "${arch}" in
        x86_64)
            DockerUrl="https://mirror.sjtu.edu.cn/docker-ce/linux/static/stable/x86_64/docker-26.1.4.tgz"
            DockerComposeUrl="https://github.com/docker/compose/releases/download/v2.27.3/docker-compose-linux-x86_64"
            ;;
        aarch64)
            DockerUrl="https://mirror.sjtu.edu.cn/docker-ce/linux/static/stable/aarch64/docker-26.1.4.tgz"
            DockerComposeUrl="https://github.com/docker/compose/releases/download/v2.27.3/docker-compose-linux-aarch64"
            ;;
        *)
            log_error "Unsupported architecture: ${arch}"
            return 1
            ;;
    esac
    
    DockerName=$(basename "${DockerUrl}")
    DockerComposeName=$(basename "${DockerComposeUrl}")
    
    return 0
}

install_binaries() {
    log_info "Installing Docker binaries..."
    
    check_dir "/tmp/lmd" || return 1
    
    download "${DockerUrl}" "/tmp/lmd/${DockerName}" || return 1
    download "${DockerComposeUrl}" "/tmp/lmd/${DockerComposeName}" || return 1
    
    log_info "Extracting Docker package..."
    if ! tar -xf "/tmp/lmd/${DockerName}" -C /tmp/lmd/; then
        log_error "Failed to extract Docker package"
        return 1
    fi
    
    check_dir "/tmp/lmd/docker" || return 1
    copy_with_permissions "/tmp/lmd/${DockerComposeName}" "/tmp/lmd/docker/docker-compose" "0755" || return 1
    
    if ! chown -R root:root /tmp/lmd/docker; then
        log_error "Failed to set ownership on Docker files"
        return 1
    fi
    
    for binary in /tmp/lmd/docker/*; do
        copy_with_permissions "${binary}" "/usr/bin/$(basename "${binary}")" "0755" || return 1
    done
    
    return 0
}

setup_systemd() {
    log_info "Setting up systemd services..."
    
    local systemd_files=(
        "containerd.service"
        "docker.socket"
        "docker.service"
    )
    
    for file in "${systemd_files[@]}"; do
        copy_with_permissions "/tmp/lmd/config/${file}" "/usr/lib/systemd/system/${file}" "0644" || return 1
    done
    
    log_info "Reloading systemd daemon..."
    if ! systemctl daemon-reload; then
        log_error "Failed to reload systemd daemon"
        return 1
    fi
    
    return 0
}

setup_docker() {
    log_info "Configuring Docker..."

    if ! getent group docker >/dev/null; then
        log_info "Creating docker group..."
        groupadd docker || {
            log_error "Failed to create docker group"
            return 1
        }
    fi
    
    check_dir "/etc/docker" || return 1
    copy_with_permissions "/tmp/lmd/config/daemon.json" "/etc/docker/daemon.json" "0644" || return 1

    if [ -S /var/run/docker.sock ]; then
        chmod 0666 /var/run/docker.sock || {
            log_error "Failed to set permissions on Docker socket"
            return 1
        }
    fi
    
    return 0
}

main() {
    log_info "Starting Docker installation..."
    
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    setup_urls || exit 1

    install_binaries || exit 1

    setup_systemd || exit 1
    
    setup_docker || exit 1
    
    log_info "Docker installation completed successfully"
}

main