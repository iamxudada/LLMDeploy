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

# Log functions
log_info() {
    printf "${GREEN}[INFO]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
}

# Configuration
SUPUEDT_LMD_WORKSPACE_PATH="{{ lmdprojectpath }}"
LMD_BASIC_IMAGES="db valkey minio clickhouse etcd milvus tdengine kkfileview registry frontend backend lmd-py"
LMD_BASIC_IMAGE_VERSION="v1"
LMD_TRAIN_IMAGE=""
LMD_FS_MW_IMAGE=""
LMD_FS_AC_IMAGE=""
LMD_VLLM_IMAGE=""

# Create workspace directory if it doesn't exist
if [ ! -d "${SUPUEDT_LMD_WORKSPACE_PATH}" ]; then
    mkdir -p "${SUPUEDT_LMD_WORKSPACE_PATH}" || {
        log_error "Failed to create workspace directory: ${SUPUEDT_LMD_WORKSPACE_PATH}"
        exit 1
    }
fi

# Check for required files
if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" ] || [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/.env" ]; then
    log_error "Required project startup files not found"
    exit 1
fi

# Download and extract volume data if needed
if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" ]; then
    log_info "Downloading lmd-volume.tar.xz..."
    wget -q --show-progress --tries=3 --timeout=60 "YOUR_DOWNLOAD_URL" -O "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" || {
        log_error "Failed to download lmd-volume.tar.xz"
        exit 1
    }
fi

# Extract volume data
if [ -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" ]; then
    log_info "Extracting volume data..."
    tar -xf "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" -C "${SUPUEDT_LMD_WORKSPACE_PATH}" || {
        log_error "Failed to extract volume data"
        exit 1
    }
else
    log_info "Pulling docker images..."
    docker-compose -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" pull || {
        log_error "Failed to pull docker images"
        exit 1
    }
fi

# Pull required images
log_info "Checking and pulling basic images..."
for image in ${LMD_BASIC_IMAGES}; do
    if ! docker images "quay.io/supiedt/${image}:${LMD_BASIC_IMAGE_VERSION}" --format "{{.Repository}}" | grep -q "${image}"; then
        log_info "Pulling image: ${image}"
        docker pull "quay.io/supiedt/${image}:${LMD_BASIC_IMAGE_VERSION}" || {
            log_error "Failed to pull image: ${image}"
            exit 1
        }
    fi
done

# Start services
log_info "Starting services..."
docker-compose -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" up -d || {
    log_error "Failed to start services"
    exit 1
}

log_info "Installation completed successfully"