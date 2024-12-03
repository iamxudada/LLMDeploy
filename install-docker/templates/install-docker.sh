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

# 获取安装包
if [[ $(uname -m) = 'x86_64' ]]; then
  DockerUrl="https://mirror.sjtu.edu.cn/docker-ce/linux/static/stable/x86_64/docker-26.1.4.tgz"
  DockerComposeUrl="https://github.com/docker/compose/releases/download/v2.27.3/docker-compose-linux-x86_64"
elif [[ $(uname -m) = 'aarch64' ]]; then
  DockerUrl="https://mirror.sjtu.edu.cn/docker-ce/linux/static/stable/aarch64/docker-26.1.4.tgz"
  DockerComposeUrl="https://github.com/docker/compose/releases/download/v2.27.3/docker-compose-linux-aarch64"
fi

DockerName=$(echo ${DockerUrl} | awk -F '/' '{print $NF}')
DockerComposeName=$(echo $DockerComposeUrl | awk -F '/' '{print $NF}')

download ${DockerUrl} "/tmp/lmd/${DockerName}"
download ${DockerComposeUrl} "/tmp/lmd/${DockerComposeName}"

# 安装
tar -xvf /tmp/lmd/${DockerName} -C /tmp/lmd/
yes|cp -a /tmp/lmd/${DockerComposeName} /tmp/lmd/docker/docker-compose
chmod -R 0755 /tmp/lmd/docker
chown -R root:root /tmp/lmd/docker
yes|cp -a /tmp/lmd/docker/* /usr/bin/

# 配置 systemd
yes | cp -a /tmp/lmd/config/containerd.service /usr/lib/systemd/system/containerd.service
yes|cp -a /tmp/lmd/config/docker.socket /usr/lib/systemd/system/docker.socket
yes|cp -a /tmp/lmd/config/docker.service /usr/lib/systemd/system/docker.service
chmod 0644 /usr/lib/systemd/system/{containerd.service,docker.socket,docker.service}

# 创建 docker 组
groupadd -f docker

# 配置 docker
mkdir -p /etc/docker
yes|cp -a /tmp/lmd/config/daemon.json /etc/docker/daemon.json
chmod 0644 /etc/docker/daemon.json

# 配置 docker.socket 权限
chmod 0666 /var/run/docker.sock

# 刷新
systemctl daemon-reload


download() {
    set +e

    local max_retries=10
    local retry_delay=10
    local url=$1
    local path=$2

    for ((i=1; i<=max_retries; i++)); do
        echo "Attempt $i of ${max_retries}..."
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