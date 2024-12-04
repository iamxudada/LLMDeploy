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

readonly SUPUEDT_LMD_WORKSPACE_PATH="{{ lmdprojectpath }}"
readonly LMD_BASIC_IMAGES="db valkey minio clickhouse etcd milvus tdengine kkfileview registry frontend backend lmd-py"
readonly LMD_BASIC_IMAGE_VERSION="v1"
readonly LMD_VOLUME_URL="YOUR_DOWNLOAD_URL"
readonly DOCKER_REGISTRY="quay.io/supiedt"
readonly LMD_TRAIN_IMAGE=""
readonly LMD_FS_MW_IMAGE=""
readonly LMD_FS_AC_IMAGE=""
readonly LMD_VLLM_IMAGE=""

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! command -v docker-compose &>/dev/null; then
        log_error "Docker Compose is not installed"
        return 1

    if ! command -v wget &>/dev/null; then
        log_error "wget is not installed"
        return 1
    
    return 0
}

setup_workspace() {
    log_info "Setting up workspace..."
    
    if [ ! -d "${SUPUEDT_LMD_WORKSPACE_PATH}" ]; then
        mkdir -p "${SUPUEDT_LMD_WORKSPACE_PATH}" || {
            log_error "Failed to create workspace directory: ${SUPUEDT_LMD_WORKSPACE_PATH}"
            return 1
        }
    fi

    local required_files=("lmd.yaml" ".env")
    for file in "${required_files[@]}"; do
        if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/${file}" ]; then
            log_error "Required file not found: ${file}"
            return 1
        fi
    done
    
    return 0
}

download_volume_data() {
    local volume_file="${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz"
    
    if [ ! -f "${volume_file}" ]; then
        log_info "Downloading lmd-volume.tar.xz..."
        wget -q --show-progress --tries=3 --timeout=60 "${LMD_VOLUME_URL}" -O "${volume_file}" || {
            log_error "Failed to download lmd-volume.tar.xz"
            return 1
        }
    else
        log_info "Volume data file already exists, skipping download"
    fi
    
    log_info "Extracting volume data..."
    tar -xf "${volume_file}" -C "${SUPUEDT_LMD_WORKSPACE_PATH}" || {
        log_error "Failed to extract volume data"
        return 1
    }
    
    return 0
}

pull_docker_images() {
    log_info "Checking and pulling basic images..."
    
    local failed_images=()
    for image in ${LMD_BASIC_IMAGES}; do
        local full_image="${DOCKER_REGISTRY}/${image}:${LMD_BASIC_IMAGE_VERSION}"
        
        if ! docker images "${full_image}" --format "{{.Repository}}" | grep -q "${image}"; then
            log_info "Pulling image: ${image}"
            if ! docker pull "${full_image}"; then
                log_warn "Failed to pull image: ${image}"
                failed_images+=("${image}")
            fi
        else
            log_info "Image already exists: ${image}"
        fi
    done
    
    if [ ${#failed_images[@]} -gt 0 ]; then
        log_error "Failed to pull the following images: ${failed_images[*]}"
        return 1
    fi
    
    return 0
}

start_services() {
    log_info "Starting services..."
    
    local compose_file="${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml"

    if ! docker-compose -f "${compose_file}" config >/dev/null; then
        log_error "Invalid docker-compose configuration"
        return 1
    fi
    
    if ! docker-compose -f "${compose_file}" up -d; then
        log_error "Failed to start services"
        return 1
    fi
    
    local services
    services=$(docker-compose -f "${compose_file}" ps --services)
    for service in ${services}; do
        if ! docker-compose -f "${compose_file}" ps "${service}" | grep -q "Up"; then
            log_error "Service failed to start: ${service}"
            return 1
        fi
    done
    
    return 0
}

cleanup() {
    if [ $? -ne 0 ]; then
        log_warn "Installation failed, cleaning up..."
        docker-compose -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" down || log_warn "Failed to stop services"
        rm -rf "${SUPUEDT_LMD_WORKSPACE_PATH}"
    fi
}

main() {
    trap cleanup EXIT
    
    log_info "Starting LMD installation..."
    
    check_prerequisites || exit 1
    
    setup_workspace || exit 1
    
    if [ ! -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd-volume.tar.xz" ]; then
        download_volume_data || exit 1
    else
        docker-compose -f "${SUPUEDT_LMD_WORKSPACE_PATH}/lmd.yaml" pull || {
            log_error "Failed to pull docker images"
            exit 1
        }
    fi
    
    pull_docker_images || exit 1
    
    start_services || exit 1
    
    log_info "Installation completed successfully"
}

main