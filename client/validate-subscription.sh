#!/usr/bin/env bash

set -euo pipefail

PROFILE_PATH="${1:-client/active-config/clash-verge-check.yaml}"

[[ -f "${PROFILE_PATH}" ]] || {
    echo "Profile not found: ${PROFILE_PATH}" >&2
    exit 1
}

required_patterns=(
    '^mode: '
    '^mixed-port: '
    '^proxies:'
    '^proxy-groups:'
    '^rules:'
    'type: vless'
    'packet-encoding: xudp'
    'reality-opts:'
    'DOMAIN-SUFFIX,openai.com,PROXY'
    'DOMAIN-SUFFIX,microsoft.com,DIRECT'
    'MATCH,PROXY'
)

for pattern in "${required_patterns[@]}"; do
    if ! grep -Eq "${pattern}" "${PROFILE_PATH}"; then
        echo "Missing required content: ${pattern}" >&2
        exit 1
    fi
done

echo "Validated profile: ${PROFILE_PATH}"
