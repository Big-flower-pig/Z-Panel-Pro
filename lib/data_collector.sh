#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ??????
# ==============================================================================
# @description    ???????????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ????
# ==============================================================================
declare -g CACHE_TTL=3
declare -g CACHE_LAST_UPDATE=0
declare -gA CACHE_DATA=()

# ==============================================================================
# ??????
# ==============================================================================

# ????
update_cache() {
    local current_time
    current_time=$(get_timestamp)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        log_debug "?????(??: ${cache_age}s, TTL: ${CACHE_TTL}s)"
        return 0
    fi

    log_debug "????..."

    # ???????????????????
    local mem_info
    mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $7, $6}')
    read -r CACHE_DATA[mem_total] CACHE_DATA[mem_used] CACHE_DATA[mem_avail] CACHE_DATA[buff_cache] <<< "${mem_info}"

    # ?????Swap??
    local swap_info
    swap_info=$(free -m | awk '/Swap:/ {print $2, $3}')
    read -r CACHE_DATA[swap_total] CACHE_DATA[swap_used] <<< "${swap_info}"

    # ??ZRAM????
    CACHE_DATA[zram_enabled]=$(is_zram_enabled && echo "1" || echo "0")

    CACHE_LAST_UPDATE=${current_time}
    log_debug "?????"
}

# ????
clear_cache() {
    CACHE_DATA=()
    CACHE_LAST_UPDATE=0
    log_debug "?????"
}

# ?????
get_cache_value() {
    local key="$1"
    echo "${CACHE_DATA[$key]:-}"
}

# ==============================================================================
# ??????
# ==============================================================================

# ??????
# @param use_cache: ???????true/false???true?
# @return: "total used avail buff_cache"
get_memory_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[mem_total]} ${CACHE_DATA[mem_used]} ${CACHE_DATA[mem_avail]} ${CACHE_DATA[buff_cache]}"
    else
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    fi
}

# ???????
# @param use_cache: ???????true/false???true?
# @return: ??????
get_memory_usage() {
    local use_cache="${1:-true}"
    local mem_total mem_used
    read -r mem_total mem_used _ _ <<< "$(get_memory_info "${use_cache}")"

    calculate_percentage "${mem_used}" "${mem_total}"
}

# ==============================================================================
# Swap????
# ==============================================================================

# ??Swap??
# @param use_cache: ???????true/false???true?
# @return: "total used"
get_swap_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[swap_total]} ${CACHE_DATA[swap_used]}"
    else
        free -m | awk '/Swap:/ {print $2, $3}'
    fi
}

# ??Swap???
# @param use_cache: ???????true/false???true?
# @return: ??????
get_swap_usage() {
    local use_cache="${1:-true}"
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info "${use_cache}")"

    calculate_percentage "${swap_used}" "${swap_total}"
}

# ==============================================================================
# ZRAM????
# ==============================================================================

# ??ZRAM????
# @return: 0????1????
is_zram_enabled() {
    swapon --show=NAME --noheadings 2>/dev/null | grep -q zram
}

# ??ZRAM????
# @return: "total_mb used_mb"
get_zram_usage() {
    if ! is_zram_enabled; then
        echo "0 0"
        return
    fi

    local zram_info
    zram_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep zram | head -1)

    if [[ -z "${zram_info}" ]]; then
        echo "0 0"
        return
    fi

    # ???????????
    local zram_total zram_used
    zram_total=$(echo "${zram_info}" | awk '{print $1}')
    zram_used=$(echo "${zram_info}" | awk '{print $2}')

    zram_total=$(convert_size_to_mb "${zram_total}")
    zram_used=$(convert_size_to_mb "${zram_used}")

    [[ -z "${zram_total}" ]] || [[ "${zram_total}" == "0" ]] && zram_total=1
    [[ -z "${zram_used}" ]] && zram_used=0

    echo "${zram_total} ${zram_used}"
}

# ??ZRAM???
# @return: ??????
get_zram_usage_percent() {
    local zram_total zram_used
    read -r zram_total zram_used <<< "$(get_zram_usage)"

    calculate_percentage "${zram_used}" "${zram_total}"
}

# ??ZRAM???JSON???
# @return: JSON???
get_zram_status() {
    if ! check_command zramctl; then
        echo '{"enabled": false}'
        return
    fi

    local zram_info
    zram_info=$(zramctl 2>/dev/null | tail -n +2)

    if [[ -z "${zram_info}" ]]; then
        echo '{"enabled": false}'
        return
    fi

    local name disk_size data_size comp_size algo
    read -r name disk_size data_size comp_size algo <<< "${zram_info}"

    local compression_ratio="0"
    if [[ -n "${data_size}" ]] && [[ -n "${comp_size}" ]] && [[ "${comp_size}" != "0" ]]; then
        compression_ratio=$(echo "${data_size} ${comp_size}" | awk '{
            data_num = $1
            comp_num = $2
            gsub(/[KMGT]/, "", data_num)
            gsub(/[KMGT]/, "", comp_num)
            if (comp_num > 0 && data_num > 0) {
                printf "%.2f", data_num / comp_num
            }
        }')
    fi

    cat <<EOF
{
    "enabled": true,
    "device": "${name}",
    "disk_size": "${disk_size}",
    "data_size": "${data_size}",
    "comp_size": "${comp_size}",
    "algorithm": "${algo}",
    "compression_ratio": "${compression_ratio}"
}
EOF
}

# ??ZRAM????
# @return: ????
get_zram_algorithm() {
    local zram_status
    zram_status=$(get_zram_status)

    if echo "${zram_status}" | grep -q "enabled.*true"; then
        echo "${zram_status}" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4
    else
        echo "unknown"
    fi
}

# ??ZRAM???
# @return: ????????
get_zram_compression_ratio() {
    local zram_status
    zram_status=$(get_zram_status)

    if echo "${zram_status}" | grep -q "enabled.*true"; then
        echo "${zram_status}" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4
    else
        echo "1.00"
    fi
}

# ==============================================================================
# CPU????
# ==============================================================================

# ??CPU???
# @return: ???
get_cpu_cores() {
    nproc 2>/dev/null || echo "1"
}

# ??CPU???
# @return: ??????
get_cpu_usage() {
    # ??CPU????????
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    echo "${cpu_usage:-0}"
}

# ==============================================================================
# ??????
# ==============================================================================

# ????????
# @param path: ??????/?
# @return: "total_mb used_mb avail_mb usage_percent"
get_disk_info() {
    local path="${1:-/}"
    df -m "${path}" | awk 'NR==2 {print $2, $3, $4, $5}'
}

# ==============================================================================
# ??????
# ==============================================================================

# ??????
# @param param: ???
# @return: ???
get_kernel_param() {
    local param="$1"
    sysctl -n "${param}" 2>/dev/null || echo ""
}

# ??swappiness?
# @return: swappiness?
get_swappiness() {
    get_kernel_param "vm.swappiness"
}

# ==============================================================================
# ??????
# ==============================================================================

# ??????
# @return: "1min 5min 15min"
get_load_average() {
    awk '{print $1, $2, $3}' /proc/loadavg
}
