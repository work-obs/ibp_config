#!/usr/bin/env bash

install_yq() {
    local usage="install_yq <hostname>"
    local hostname="${1:?$usage}"

    echo "Installing yq on $hostname..."
    local yq_binary="yq_linux_amd64"
    # https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64

    ssh "$hostname" "
        sudo wget 'https://github.com/mikefarah/yq/releases/latest/download/${yq_binary}' -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        echo 'yq installed successfully'
    "
}

