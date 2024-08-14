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

# 获取安装包
if [[ $(uname -m) = 'x86_64' ]]; then
  DockerUrl="http://39.129.20.152:30083/api/public/dl/3vs2vfyz/Dependencies/docker/docker-20.10.24-x86_64.tgz"
  DockerComposeUrl="http://39.129.20.152:30083/api/public/dl/xKkUBduX/Dependencies/docker/docker-compose-linux-x86_64"
elif [[ $(uname -m) = 'aarch64' ]]; then
  DockerUrl="http://39.129.20.152:30083/api/public/dl/j0YExKvH/Dependencies/docker/docker-20.10.24-aarch64.tgz"
  DockerComposeUrl="http://39.129.20.152:30083/api/public/dl/VyiUjb_0/Dependencies/docker/docker-compose-linux-aarch64"
fi

DockerName=$(echo $DockerUrl | awk -F '/' '{print $NF}')
DockerComposeName=$(echo $DockerComposeUrl | awk -F '/' '{print $NF}')

wget -c -q -O /tmp/lmd/$DockerName $DockerUrl
wget -c -q -O /tmp/lmd/$DockerComposeName $DockerComposeUrl

# 安装
tar -xvf /tmp/lmd/$DockerName -C /tmp/lmd/
yes|cp -a /tmp/lmd/$DockerComposeName /tmp/lmd/docker/docker-compose
chmod -R 0755 /tmp/lmd/docker
chown -R root:root /tmp/lmd/docker
yes|cp -a /tmp/lmd/docker/* /usr/bin/

# 配置 systemd
yes|cp -a /tmp/lmd/services/containerd.service /usr/lib/systemd/system/containerd.service
yes|cp -a /tmp/lmd/services/docker.socket /usr/lib/systemd/system/docker.socket
yes|cp -a /tmp/lmd/services/docker.service /usr/lib/systemd/system/docker.service

chmod 0644 /usr/lib/systemd/system/docker.socket
chmod 0644 /usr/lib/systemd/system/docker.service
chmod 0644 /usr/lib/systemd/system/containerd.service

# 创建 docker 组
groupadd -f docker

# 配置 docker
mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "insecure-registries": ["{{ groups.master }}:30062"],
  "data-root": "/data/Dependencies/docker",
  "default-address-pools" : [
    {
      "base" : "172.17.0.0/12",
      "size" : 12
    },
    {
      "base" : "192.168.0.0/16",
      "size" : 16
    }
  ]
}
EOF

# 配置 docker.socket 权限
chmod 0666 /var/run/docker.sock

# 刷新
systemctl daemon-reload