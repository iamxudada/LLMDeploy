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

ASCEND_ROOT="/usr/local/Ascend"
TMP_DRIVERS="/tmp/lmd/drivers"

# 卸载组件
uninstall_component() {
    local component_path="$1"
    local uninstall_script="$2"
    local component_name="$3"

    if [ -d "${component_path}" ]; then
        if [ -f "${component_path}/${uninstall_script}" ]; then
            bash "${component_path}/${uninstall_script}"
        else
            rm -rf "${component_path}"
        fi
    else
        printf "${YELLOW}%s PATH not found!${RESET}\n" "${component_name}"
    fi
}

# 安装驱动
install_driver() {
    local driver_file="$1"
    local install_options="$2"
    
    echo y | bash "${TMP_DRIVERS}/${driver_file}" ${install_options} || {
        printf "${RED}Failed to install %s${RESET}\n" "${driver_file}"
        exit 1
    }
}

download() {
    set +e

    local max_retries=10
    local retry_delay=10
    local url="$1"
    local path="$2"

    printf "Downloading %s to %s\n" "${url}" "${path}"
    for ((i=1; i<=max_retries; i++)); do
        printf "Attempt %d of %d at %s...\n" "$i" "$max_retries" "$(date)"
        curl -fsSL -o "${path}" "${url}"
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}Download successful!${RESET}\n"
            return 0
        else
            printf "${YELLOW}Download failed with error code %d. Retrying in %d seconds...${RESET}\n" "$?" "$retry_delay"
            sleep ${retry_delay}
        fi
    done

    printf "${RED}All download attempts failed. Exiting.${RESET}\n"
    return 1
}

mkdir -p ${TMP_DRIVERS}
os_architecture=$(uname -m)
driver_install_type=$(lspci | grep 'Processing accelerators: Huawei Technologies Co., Ltd. Device' | awk -F'Device ' '{print $2}' | awk -F' ' '{print $1}' | uniq)

# 获取驱动文件
case "${os_architecture} ${driver_install_type}" in
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
        printf "${RED}Unsupported Device Type: %s${RESET}\n" "${driver_install_type}"
        exit 1
        ;;
esac

DriverDName=$(basename ${DriverDUrl})
DriverFName=$(basename ${DriverFUrl})
DriverDRName=$(basename ${DriverDRUrl})

# 下载驱动
download ${DriverDUrl} "${TMP_DRIVERS}/${DriverDName}"
download ${DriverFUrl} "${TMP_DRIVERS}/${DriverFName}"
download ${DriverDRUrl} "${TMP_DRIVERS}/${DriverDRName}"

# 卸载旧驱动
uninstall_component "${ASCEND_ROOT}/Ascend-Docker-Runtime" "script/uninstall.sh" "Ascend-Docker-Runtime"
uninstall_component "${ASCEND_ROOT}/firmware" "script/uninstall.sh" "Firmware"
uninstall_component "${ASCEND_ROOT}/driver" "script/run_driver_uninstall.sh" "Driver"

systemctl daemon-reload

# 安装新驱动
install_driver "${DriverDName}" "--quiet --full --install-for-all"
source ${ASCEND_ROOT}/driver/bin/setenv.bash
echo "source ${ASCEND_ROOT}/driver/bin/setenv.bash" > /etc/profile.d/ascend_env.sh

install_driver "${DriverFName}" "--quiet --full"
install_driver "${DriverDRName}" "--install"

# 重启 docker
systemctl daemon-reload
systemctl restart docker