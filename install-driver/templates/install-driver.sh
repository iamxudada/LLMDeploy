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

readonly ASCEND_ROOT="/usr/local/Ascend"
readonly TMP_DRIVERS="/tmp/lmd/drivers"

log_info() {
    printf "${GREEN}[INFO]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
        exit 1
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

uninstall_component() {
    local component_path="$1"
    local uninstall_script="$2"
    local component_name="$3"

    log_info "Uninstalling ${component_name}..."
    if [ -d "${component_path}" ]; then
        if [ -f "${component_path}/${uninstall_script}" ]; then
            bash "${component_path}/${uninstall_script}" || {
                log_warn "Failed to run uninstall script for ${component_name}"
            }
        else
            rm -rf "${component_path}" || {
                log_warn "Failed to remove ${component_name} directory"
            }
        fi
    else
        log_warn "${component_name} PATH not found"
    fi
}

install_driver() {
    local driver_file="$1"
    local install_options="$2"
    
    log_info "Installing ${driver_file}..."
    if [ ! -f "${TMP_DRIVERS}/${driver_file}" ]; then
        log_error "Driver file not found: ${driver_file}"
        return 1
    }
    
    echo y | bash "${TMP_DRIVERS}/${driver_file}" ${install_options} || {
        log_error "Failed to install ${driver_file}"
        return 1
    }
    
    log_info "Successfully installed ${driver_file}"
    return 0
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

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${TMP_DRIVERS}"
}

setup_urls() {
    local os_arch="$1"
    local driver_type="$2"
    
    case "${os_arch} ${driver_type}" in
        "x86_64 d801")
            DriverDUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.2.1/Ascend-hdk-910-npu-driver_23.0.2_linux-x86-64.run"
            DriverFUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.2.1/Ascend-hdk-910-npu-firmware_7.1.0.4.220.run"
            DriverDRUrl="https://gitee.com/ascend/ascend-docker-runtime/releases/download/v5.0.1-Patch1/Ascend-docker-runtime_5.0.1.1_linux-x86_64.run"
            ;;
        "aarch64 d801")
            DriverDUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.0/Ascend-hdk-910-npu-driver_23.0.0_linux-aarch64.run"
            DriverFUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.0/Ascend-hdk-910-npu-firmware_7.1.0.3.220.run"
            DriverDRUrl="https://gitee.com/ascend/ascend-docker-runtime/releases/download/v5.0.1-Patch1/Ascend-docker-runtime_5.0.1.1_linux-aarch64.run"
            ;;
        "aarch64 d802")
            DriverDUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.3/Ascend-hdk-910b-npu-driver_23.0.3_linux-aarch64.run"
            DriverFUrl="https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/Ascend%20HDK/Ascend%20HDK%2023.0.3/Ascend-hdk-910b-npu-firmware_7.1.0.5.220.run"
            DriverDRUrl="https://gitee.com/ascend/ascend-docker-runtime/releases/download/v5.0.1-Patch1/Ascend-docker-runtime_5.0.1.1_linux-aarch64.run"
            ;;
        *)
            log_error "Unsupported architecture/device combination: ${os_arch} ${driver_type}"
            return 1
            ;;
    esac
    
    return 0
}

detect_hardware() {
    local driver_type
    driver_type=$(lspci | grep 'Processing accelerators: Huawei Technologies Co., Ltd. Device' | awk -F'Device ' '{print $2}' | awk -F' ' '{print $1}' | uniq)
    
    if [ -z "${driver_type}" ]; then
        log_error "No supported Huawei NPU device found"
        return 1
    fi
    
    echo "${driver_type}"
    return 0
}

main() {
    log_info "Starting Ascend driver installation..."
    
    check_root
    check_dir "${TMP_DRIVERS}" || exit 1
    
    local os_arch
    os_arch=$(uname -m)
    local driver_type
    driver_type=$(detect_hardware) || exit 1
    
    setup_urls "${os_arch}" "${driver_type}" || exit 1
    
    DriverDName=$(basename "${DriverDUrl}")
    DriverFName=$(basename "${DriverFUrl}")
    DriverDRName=$(basename "${DriverDRUrl}")
    
    log_info "Downloading drivers..."
    download "${DriverDUrl}" "${TMP_DRIVERS}/${DriverDName}" || exit 1
    download "${DriverFUrl}" "${TMP_DRIVERS}/${DriverFName}" || exit 1
    download "${DriverDRUrl}" "${TMP_DRIVERS}/${DriverDRName}" || exit 1
    
    log_info "Uninstalling old drivers..."
    uninstall_component "${ASCEND_ROOT}/Ascend-Docker-Runtime" "script/uninstall.sh" "Ascend-Docker-Runtime"
    uninstall_component "${ASCEND_ROOT}/firmware" "script/uninstall.sh" "Firmware"
    uninstall_component "${ASCEND_ROOT}/driver" "script/run_driver_uninstall.sh" "Driver"
    
    systemctl daemon-reload
    
    log_info "Installing new drivers..."
    install_driver "${DriverDName}" "--quiet --full --install-for-all" || exit 1
    
    log_info "Setting up environment..."
    source "${ASCEND_ROOT}/driver/bin/setenv.bash"
    echo "source ${ASCEND_ROOT}/driver/bin/setenv.bash" > /etc/profile.d/ascend_env.sh
    
    install_driver "${DriverFName}" "--quiet --full" || exit 1
    install_driver "${DriverDRName}" "--install" || exit 1
    
    log_info "Restarting Docker service..."
    systemctl daemon-reload
    systemctl restart docker || {
        log_error "Failed to restart Docker service"
        exit 1
    }
    
    log_info "Driver installation completed successfully"
}

trap cleanup EXIT
main