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

mkdir -p /tmp/lmd/drivers
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
    echo -e "${RED}Unsupported Device Type: ${driver_install_type} ${RESET}"
    exit 1
esac
DriverDName=$(echo ${DriverDUrl} | awk -F '/' '{print $NF}')
DriverFName=$(echo ${DriverFUrl} | awk -F '/' '{print $NF}')
DriverDRName=$(echo ${DriverDRUrl} | awk -F '/' '{print $NF}')

# 覆盖下载驱动

download ${DriverDUrl} "/tmp/lmd/drivers/${DriverDName}"
download ${DriverFUrl} "/tmp/lmd/drivers/${DriverFName}"
download ${DriverDRUrl} "/tmp/lmd/drivers/${DriverDRName}"

# 安装驱动
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

systemctl daemon-reload

echo y | bash /tmp/lmd/drivers/$DriverDName --quiet --full --install-for-all
source /usr/local/Ascend/driver/bin/setenv.bash
echo "source /usr/local/Ascend/driver/bin/setenv.bash" > /etc/profile.d/ascend_env.sh
echo y | bash /tmp/lmd/drivers/$DriverFName --quiet --full
echo y | bash /tmp/lmd/drivers/$DriverDRName --install


# 重启 docker
systemctl deamon-reload
systemctl restart docker


download() {
    set +e

    local max_retries=10
    local retry_delay=10
    local url=$1
    local path=$2

    for ((i=1; i<=max_retries; i++)); do
        echo "Attempt $i of $max_retries..."
        curl -fsSL -o "${path}" "${url}"
        if [[ $? -eq 0 ]]; then
            return 0
        else
            echo "Download failed with error code $?. Retrying in ${retry_delay} seconds..."
            sleep ${retry_delay}
        fi
    done

    echo "All attempts failed. Exiting."
    return 1
}