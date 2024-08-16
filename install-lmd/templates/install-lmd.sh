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

SUPUEDT_LMD_WORKSPACE_PATH="/data/applications/lmd"
LMD_BASIC_IMAGES="db valkey minio clickhouse etcd milvus tdengine kkfileview registry frontend backend lmd-py"  # 基础镜像
LMD_BASIC_IMAGE_VERSION="v1"
LMD_TRAIN_IMAGE=""  # 训练镜像
LMD_FS_MW_IMAGE=""  # fastchat modelwork 镜像
LMD_FS_AC_IMAGE=""  # fastchat api contoller 镜像
LMD_VLLM_IMAGE=""   # vllm 镜像（若平台不支持，请勿填）


if [ ! -d "${SUPUEDT_LMD_WORKSPACE_PATH}" ]; then
    mkdir -p ${SUPUEDT_LMD_WORKSPACE_PATH}
fi


if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" ] && [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/.env" ]; then
    echo -e "${RED}未发现项目启动文件 ${RESET}"
    exit 1
if

if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" ]; then
    wget -q 


if [ -d "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" ]; then
    tar -xzf ${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz -C ${SUPUEDT_LMD_WORKSPACE_PATH}
else
    docker-compose -f ${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml pull
if

for image in ${LMD_BASIC_IMAGES}; do
    is_ready=$(docker images | grep ${image})
    if [ ! -a ${is_ready} ]; then
        docker pull quay.io/supiedt/${image}:${LMD_BASIC_IMAGE_VERSION}
    fi
done

docker-compose -f ${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml up -d