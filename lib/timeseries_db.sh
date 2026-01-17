#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 时序数据库适配器
# ==============================================================================
# @description    时序数据库适配器，支持InfluxDB、TimescaleDB、Prometheus
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 时序数据库配置
# ==============================================================================
declare -gA TSDB_CONFIG=(
    [backend]="influxdb"              # influxdb/timescaledb/prometheus/memory
    [host]="localhost"
    [port]="8086"
    [database]="zpanel"
    [username]=""
    [password]=""
    [retention_policy]="30d"
    [batch_size]="1000"
    [flush_interval]="10"
    [compression]="gzip"
    [memory_max_points]="100000"
    [memory_max_size]="100M"
)

# ==============================================================================
# 时序数据库状态
# ==============================================================================
declare -g TSDB_CONNECTED=false
declare -gA TSDB_MEMORY_BUFFER=()
declare -gA TSDB_SERIES=()
declare -gA TSDB_TAGS=()

# ==============================================================================
# 数据点结构
# ==============================================================================
# 数据点格式: measurement,timestamp,field1=value1,field2=value2,tags
declare -gA TSDB_DATA_POINTS=()

# ==============================================================================
# InfluxDB适配器
# ==============================================================================
# 连接InfluxDB
influxdb_connect() {
    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    if ! command -v influx &> /dev/null; then
        log_error "influx 命令未找到，请安装InfluxDB客户端"
        return 1
    fi

    # 测试连接
    local test_result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        test_result=$(influx -host "${host}" -port "${port}" -username "${username}" -password "${password}" -database "${database}" -execute "SHOW DATABASES" 2>&1)
    else
        test_result=$(influx -host "${host}" -port "${port}" -database "${database}" -execute "SHOW DATABASES" 2>&1)
    fi

    if echo "${test_result}" | grep -q "connection refused"; then
        log_error "无法连接到InfluxDB: ${host}:${port}"
        return 1
    fi

    # 创建数据库（如果不存在）
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        influx -host "${host}" -port "${port}" -username "${username}" -password "${password}" -execute "CREATE DATABASE IF NOT EXISTS ${database}" 2>/dev/null
    else
        influx -host "${host}" -port "${port}" -execute "CREATE DATABASE IF NOT EXISTS ${database}" 2>/dev/null
    fi

    TSDB_CONNECTED=true
    log_info "已连接到InfluxDB: ${host}:${port}/${database}"
    return 0
}

# 写入InfluxDB
influxdb_write() {
    local measurement="$1"
    local timestamp="$2"
    shift 2
    local fields=("$@")
    local tags="${TSDB_TAGS[${measurement}]:-}"

    # 构建行协议
    local line="${measurement}"

    # 添加tags
    if [[ -n "${tags}" ]]; then
        line+=",${tags}"
    fi

    # 添加fields
    line+=" "
    local first=true
    for field in "${fields[@]}"; do
        if [[ "${first}" == "true" ]]; then
            line+="${field}"
            first=false
        else
            line+=",${field}"
        fi
    done

    # 添加timestamp
    if [[ -n "${timestamp}" ]]; then
        line+=" ${timestamp}"
    fi

    # 写入数据
    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    local result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        result=$(echo -n "${line}" | influx -host "${host}" -port "${port}" -username "${username}" -password "${password}" -database "${database}" -import -path /dev/stdin 2>&1)
    else
        result=$(echo -n "${line}" | influx -host "${host}" -port "${port}" -database "${database}" -import -path /dev/stdin 2>&1)
    fi

    if echo "${result}" | grep -q "error"; then
        log_error "InfluxDB写入失败: ${result}"
        return 1
    fi

    return 0
}

# 查询InfluxDB
influxdb_query() {
    local query="$1"

    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    local result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        result=$(influx -host "${host}" -port "${port}" -username "${username}" -password "${password}" -database "${database}" -execute "${query}" -format json 2>&1)
    else
        result=$(influx -host "${host}" -port "${port}" -database "${database}" -execute "${query}" -format json 2>&1)
    fi

    if echo "${result}" | grep -q "error"; then
        log_error "InfluxDB查询失败: ${result}"
        return 1
    fi

    echo "${result}"
    return 0
}

# ==============================================================================
# TimescaleDB适配器
# ==============================================================================
# 连接TimescaleDB
timescaledb_connect() {
    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    if ! command -v psql &> /dev/null; then
        log_error "psql 命令未找到，请安装PostgreSQL客户端"
        return 1
    fi

    # 测试连接
    local test_result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        test_result=$(PGPASSWORD="${password}" psql -h "${host}" -p "${port}" -U "${username}" -d "${database}" -c "SELECT 1" 2>&1)
    else
        test_result=$(psql -h "${host}" -p "${port}" -d "${database}" -c "SELECT 1" 2>&1)
    fi

    if echo "${test_result}" | grep -q "could not connect"; then
        log_error "无法连接到TimescaleDB: ${host}:${port}"
        return 1
    fi

    TSDB_CONNECTED=true
    log_info "已连接到TimescaleDB: ${host}:${port}/${database}"
    return 0
}

# 写入TimescaleDB
timescaledb_write() {
    local table="$1"
    local timestamp="$2"
    shift 2
    local fields=("$@")

    # 构建SQL
    local columns="time"
    local values="to_timestamp(${timestamp})"

    for field in "${fields[@]}"; do
        local key="${field%%=*}"
        local value="${field#*=}"
        columns+=", ${key}"
        values+=", ${value}"
    done

    local sql="INSERT INTO ${table} (${columns}) VALUES (${values})"

    # 执行SQL
    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    local result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        result=$(PGPASSWORD="${password}" psql -h "${host}" -p "${port}" -U "${username}" -d "${database}" -c "${sql}" 2>&1)
    else
        result=$(psql -h "${host}" -p "${port}" -d "${database}" -c "${sql}" 2>&1)
    fi

    if echo "${result}" | grep -q "ERROR"; then
        log_error "TimescaleDB写入失败: ${result}"
        return 1
    fi

    return 0
}

# 查询TimescaleDB
timescaledb_query() {
    local query="$1"

    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local username="${TSDB_CONFIG[username]}"
    local password="${TSDB_CONFIG[password]}"
    local database="${TSDB_CONFIG[database]}"

    local result
    if [[ -n "${username}" ]] && [[ -n "${password}" ]]; then
        result=$(PGPASSWORD="${password}" psql -h "${host}" -p "${port}" -U "${username}" -d "${database}" -c "${query}" -t 2>&1)
    else
        result=$(psql -h "${host}" -p "${port}" -d "${database}" -c "${query}" -t 2>&1)
    fi

    if echo "${result}" | grep -q "ERROR"; then
        log_error "TimescaleDB查询失败: ${result}"
        return 1
    fi

    echo "${result}"
    return 0
}

# ==============================================================================
# Prometheus适配器
# ==============================================================================
# 写入Prometheus（通过Pushgateway）
prometheus_write() {
    local measurement="$1"
    local timestamp="$2"
    shift 2
    local fields=("$@")

    local host="${TSDB_CONFIG[host]}"
    local port="${TSDB_CONFIG[port]}"
    local url="http://${host}:${port}/metrics/job/zpanel"

    for field in "${fields[@]}"; do
        local metric_name="${measurement}_${field%%=*}"
        local metric_value="${field#*=}"

        # 添加到Pushgateway
        local metric_data="${metric_name} ${metric_value} ${timestamp}"

        curl -X POST -d "${metric_data}" "${url}" 2>/dev/null || true
    done

    return 0
}

# ==============================================================================
# 内存后端（用于开发和测试）
# ==============================================================================
# 写入内存
memory_write() {
    local measurement="$1"
    local timestamp="$2"
    shift 2
    local fields=("$@")

    local series_key="${measurement}"
    local data_point="${timestamp}"

    for field in "${fields[@]}"; do
        data_point+="|${field}"
    done

    # 添加到序列
    local series="${TSDB_SERIES[${series_key}]:-}"
    series+="${data_point}"$'\n'

    TSDB_SERIES["${series_key}"]="${series}"

    # 检查内存限制
    local max_points="${TSDB_CONFIG[memory_max_points]}"
    local point_count=$(echo "${series}" | wc -l)

    if [[ ${point_count} -gt ${max_points} ]]; then
        # 删除旧数据点
        TSDB_SERIES["${series_key}"]=$(echo "${series}" | tail -n ${max_points})
    fi

    return 0
}

# 查询内存
memory_query() {
    local measurement="$1"
    local start_time="${2:-0}"
    local end_time="${3:-$(date +%s)}"

    local series="${TSDB_SERIES[${measurement}]:-}"

    if [[ -z "${series}" ]]; then
        return 1
    fi

    # 过滤时间范围
    echo "${series}" | while IFS='|' read -r timestamp rest; do
        if [[ ${timestamp} -ge ${start_time} ]] && [[ ${timestamp} -le ${end_time} ]]; then
            echo "${timestamp}|${rest}"
        fi
    done

    return 0
}

# ==============================================================================
# 通用API
# ==============================================================================
# 连接时序数据库
connect_tsdb() {
    local backend="${TSDB_CONFIG[backend]}"

    log_info "连接时序数据库: ${backend}"

    case "${backend}" in
        influxdb)
            influxdb_connect
            ;;
        timescaledb)
            timescaledb_connect
            ;;
        prometheus)
            # Prometheus通过Pushgateway写入，不需要连接
            TSDB_CONNECTED=true
            log_info "Prometheus模式已启用"
            ;;
        memory)
            TSDB_CONNECTED=true
            log_info "内存模式已启用"
            ;;
        *)
            log_error "未知时序数据库后端: ${backend}"
            return 1
            ;;
    esac

    return $?
}

# 写入数据点
write_tsdb() {
    local measurement="$1"
    local timestamp="${2:-$(date +%s000000000)}"  # 纳秒时间戳
    shift 2
    local fields=("$@")

    if [[ "${TSDB_CONNECTED}" != "true" ]]; then
        log_warning "时序数据库未连接，跳过写入"
        return 1
    fi

    local backend="${TSDB_CONFIG[backend]}"

    case "${backend}" in
        influxdb)
            influxdb_write "${measurement}" "${timestamp}" "${fields[@]}"
            ;;
        timescaledb)
            timescaledb_write "${measurement}" "${timestamp}" "${fields[@]}"
            ;;
        prometheus)
            prometheus_write "${measurement}" "${timestamp}" "${fields[@]}"
            ;;
        memory)
            memory_write "${measurement}" "${timestamp}" "${fields[@]}"
            ;;
        *)
            log_error "未知时序数据库后端: ${backend}"
            return 1
            ;;
    esac

    return $?
}

# 查询数据
query_tsdb() {
    local query="$1"

    if [[ "${TSDB_CONNECTED}" != "true" ]]; then
        log_warning "时序数据库未连接，跳过查询"
        return 1
    fi

    local backend="${TSDB_CONFIG[backend]}"

    case "${backend}" in
        influxdb)
            influxdb_query "${query}"
            ;;
        timescaledb)
            timescaledb_query "${query}"
            ;;
        prometheus)
            # Prometheus查询需要通过HTTP API
            log_error "Prometheus查询未实现"
            return 1
            ;;
        memory)
            memory_query "${query}"
            ;;
        *)
            log_error "未知时序数据库后端: ${backend}"
            return 1
            ;;
    esac

    return $?
}

# 批量写入
batch_write_tsdb() {
    local measurement="$1"
    shift
    local data_points=("$@")

    for data_point in "${data_points[@]}"; do
        local timestamp=$(echo "${data_point}" | cut -d'|' -f1)
        local fields=$(echo "${data_point}" | cut -d'|' -f2-)

        write_tsdb "${measurement}" "${timestamp}" "${fields}"
    done

    return 0
}

# ==============================================================================
# 标签管理
# ==============================================================================
# 设置标签
set_tsdb_tags() {
    local measurement="$1"
    shift
    local tags=("$@")

    local tags_str=""
    for tag in "${tags[@]}"; do
        if [[ -z "${tags_str}" ]]; then
            tags_str="${tag}"
        else
            tags_str+=",${tag}"
        fi
    done

    TSDB_TAGS["${measurement}"]="${tags_str}"
}

# 获取标签
get_tsdb_tags() {
    local measurement="$1"
    echo "${TSDB_TAGS[${measurement}]:-}"
}

# ==============================================================================
# 时间序列数据
# ==============================================================================
# 获取时间序列数据
get_time_series_data() {
    local measurement="$1"
    local count="${2:-10}"
    local start_time="${3:-$(($(date +%s) - 3600))}"
    local end_time="${4:-$(date +%s)}"

    local backend="${TSDB_CONFIG[backend]}"

    case "${backend}" in
        influxdb)
            local query="SELECT * FROM ${measurement} WHERE time >= ${start_time}s AND time <= ${end_time}s ORDER BY time DESC LIMIT ${count}"
            influxdb_query "${query}"
            ;;
        timescaledb)
            local query="SELECT * FROM ${measurement} WHERE time >= to_timestamp(${start_time}) AND time <= to_timestamp(${end_time}) ORDER BY time DESC LIMIT ${count}"
            timescaledb_query "${query}"
            ;;
        memory)
            memory_query "${measurement}" "${start_time}" "${end_time}" | head -n ${count}
            ;;
        *)
            log_error "未知时序数据库后端: ${backend}"
            return 1
            ;;
    esac

    return 0
}

# 聚合查询
aggregate_tsdb() {
    local measurement="$1"
    local field="$2"
    local function="${3:-mean}"
    local interval="${4:-1m}"
    local start_time="${5:-$(($(date +%s) - 3600))}"
    local end_time="${6:-$(date +%s)}"

    local backend="${TSDB_CONFIG[backend]}"

    case "${backend}" in
        influxdb)
            local query="SELECT ${function}(${field}) FROM ${measurement} WHERE time >= ${start_time}s AND time <= ${end_time}s GROUP BY time(${interval})"
            influxdb_query "${query}"
            ;;
        timescaledb)
            local query="SELECT time_bucket('${interval}', time) AS bucket, ${function}(${field}) FROM ${measurement} WHERE time >= to_timestamp(${start_time}) AND time <= to_timestamp(${end_time}) GROUP BY bucket ORDER BY bucket"
            timescaledb_query "${query}"
            ;;
        *)
            log_error "聚合查询不支持: ${backend}"
            return 1
            ;;
    esac

    return 0
}

# ==============================================================================
# 数据导出/导入
# ==============================================================================
# 导出数据
export_tsdb_data() {
    local measurement="$1"
    local start_time="${2:-$(($(date +%s) - 86400))}"
    local end_time="${3:-$(date +%s)}"
    local output_file="${4:-/tmp/${measurement}_export.json}"

    local data=$(get_time_series_data "${measurement}" 100000 "${start_time}" "${end_time}")

    echo "${data}" > "${output_file}"

    log_info "数据已导出到: ${output_file}"
    echo "${output_file}"
}

# 导入数据
import_tsdb_data() {
    local input_file="$1"

    if [[ ! -f "${input_file}" ]]; then
        log_error "文件不存在: ${input_file}"
        return 1
    fi

    local measurement=$(basename "${input_file}" .json | cut -d'_' -f1)

    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            # 解析并写入数据
            # 这里需要根据实际格式进行解析
            write_tsdb "${measurement}" "${line}"
        fi
    done < "${input_file}"

    log_info "数据已导入: ${input_file}"
    return 0
}

# ==============================================================================
# 清理和维护
# ==============================================================================
# 清理旧数据
cleanup_old_data() {
    local retention="${TSDB_CONFIG[retention_policy]}"
    local cutoff_time=$(($(date +%s) - $(echo "${retention}" | sed 's/d/*86400/' | bc)))

    local backend="${TSDB_CONFIG[backend]}"

    case "${backend}" in
        influxdb)
            # InfluxDB自动处理保留策略
            log_debug "InfluxDB使用保留策略: ${retention}"
            ;;
        timescaledb)
            local query="DELETE FROM metrics WHERE time < to_timestamp(${cutoff_time})"
            timescaledb_query "${query}"
            log_info "已清理旧数据（保留: ${retention}）"
            ;;
        memory)
            # 清理内存中的旧数据
            for key in "${!TSDB_SERIES[@]}"; do
                local series="${TSDB_SERIES[${key}]}"
                TSDB_SERIES["${key}"]=$(echo "${series}" | while IFS='|' read -r timestamp rest; do
                    if [[ ${timestamp} -ge ${cutoff_time} ]]; then
                        echo "${timestamp}|${rest}"
                    fi
                done)
            done
            log_info "已清理内存中的旧数据"
            ;;
    esac

    return 0
}

# 获取统计信息
get_tsdb_stats() {
    local backend="${TSDB_CONFIG[backend]}"
    local stats=""

    case "${backend}" in
        influxdb)
            local query="SHOW MEASUREMENTS"
            local measurements=$(influxdb_query "${query}")
            stats=$(cat <<EOF
{
    "backend": "influxdb",
    "host": "${TSDB_CONFIG[host]}",
    "port": "${TSDB_CONFIG[port]}",
    "database": "${TSDB_CONFIG[database]}",
    "measurements": ${measurements}
}
EOF
)
            ;;
        timescaledb)
            local query="SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
            local tables=$(timescaledb_query "${query}")
            stats=$(cat <<EOF
{
    "backend": "timescaledb",
    "host": "${TSDB_CONFIG[host]}",
    "port": "${TSDB_CONFIG[port]}",
    "database": "${TSDB_CONFIG[database]}",
    "tables": "${tables}"
}
EOF
)
            ;;
        memory)
            local series_count=${#TSDB_SERIES[@]}
            local total_points=0
            for series in "${TSDB_SERIES[@]}"; do
                total_points+=$(echo "${series}" | wc -l)
            done

            stats=$(cat <<EOF
{
    "backend": "memory",
    "series_count": ${series_count},
    "total_points": ${total_points}
}
EOF
)
            ;;
    esac

    echo "${stats}"
}

# ==============================================================================
# 初始化
# ==============================================================================
# 初始化时序数据库
init_tsdb() {
    log_info "初始化时序数据库..."

    # 创建数据目录
    mkdir -p "/opt/Z-Panel-Pro/data/tsdb"

    # 连接数据库
    connect_tsdb

    if [[ "${TSDB_CONNECTED}" == "true" ]]; then
        log_info "时序数据库初始化完成"
        return 0
    else
        log_warning "时序数据库连接失败，使用内存模式"
        TSDB_CONFIG[backend]="memory"
        TSDB_CONNECTED=true
        return 0
    fi
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f connect_tsdb
export -f write_tsdb
export -f query_tsdb
export -f batch_write_tsdb
export -f set_tsdb_tags
export -f get_tsdb_tags
export -f get_time_series_data
export -f aggregate_tsdb
export -f export_tsdb_data
export -f import_tsdb_data
export -f cleanup_old_data
export -f get_tsdb_stats
export -f init_tsdb
