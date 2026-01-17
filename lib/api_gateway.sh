#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - API网关
# ==============================================================================
# @description    统一API网关，提供认证、限流、路由、协议转换
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# API网关配置
# ==============================================================================
declare -gA API_GATEWAY_CONFIG=(
    [host]="0.0.0.0"
    [port]="8081"
    [max_connections]="1000"
    [request_timeout]="30"
    [auth_enabled]="true"
    [rate_limit_enabled]="true"
    [rate_limit_requests]="100"
    [rate_limit_window]="60"
    [cors_enabled]="true"
    [cors_origin]="*"
    [cors_methods]="GET,POST,PUT,DELETE,OPTIONS"
    [cors_headers]="Content-Type,Authorization,X-Session-Token"
    [ssl_enabled]="false"
    [ssl_cert]=""
    [ssl_key]=""
    [log_requests]="true"
    [log_level]="info"
)

# ==============================================================================
# 路由配置
# ==============================================================================
declare -gA API_ROUTES=(
    # 系统路由
    [/api/v1/system/info]="get_system_info"
    [/api/v1/system/metrics]="get_system_metrics"
    [/api/v1/system/health]="get_health_status"

    # 内存路由
    [/api/v1/memory/info]="get_memory_info"
    [/api/v1/memory/usage]="get_memory_usage"
    [/api/v1/memory/optimize]="optimize_memory"

    # ZRAM路由
    [/api/v1/zram/info]="get_zram_info"
    [/api/v1/zram/usage]="get_zram_usage"
    [/api/v1/zram/start]="start_zram"
    [/api/v1/zram/stop]="stop_zram"
    [/api/v1/zram/resize]="resize_zram"

    # 决策引擎路由
    [/api/v1/decision_engine/status]="get_decision_engine_status"
    [/api/v1/decision_engine/decisions]="get_recent_decisions"
    [/api/v1/decision_engine/start]="start_decision_engine"
    [/api/v1/decision_engine/stop]="stop_decision_engine"

    # 配置路由
    [/api/v1/config]="get_config"
    [/api/v1/config/update]="update_config"

    # 认证路由
    [/api/v1/auth/login]="handle_login"
    [/api/v1/auth/logout]="handle_logout"
    [/api/v1/auth/refresh]="handle_refresh_token"

    # 监控路由
    [/api/v1/monitor/status]="get_monitor_status"
    [/api/v1/monitor/subscribe]="subscribe_monitor"
    [/api/v1/monitor/unsubscribe]="unsubscribe_monitor"
)

# ==============================================================================
# 限流配置
# ==============================================================================
declare -gA RATE_LIMIT_STATE=()
declare -gA RATE_LIMIT_WINDOWS=()

# ==============================================================================
# 认证配置
# ==============================================================================
declare -gA AUTH_SESSIONS=()
declare -gA AUTH_TOKENS=()
declare -gA AUTH_REFRESH_TOKENS=()

# ==============================================================================
# API网关状态
# ==============================================================================
declare -g API_GATEWAY_RUNNING=false
declare -g API_GATEWAY_PID=""
declare -gA API_GATEWAY_CONNECTIONS=()

# ==============================================================================
# 初始化API网关
# ==============================================================================
init_api_gateway() {
    log_info "初始化API网关..."

    # 创建临时目录
    mkdir -p "/opt/Z-Panel-Pro/tmp/sessions"
    mkdir -p "/opt/Z-Panel-Pro/tmp/rate_limit"
    mkdir -p "/opt/Z-Panel-Pro/logs/api"

    # 加载路由配置
    load_routes_config

    # 初始化限流状态
    init_rate_limit

    # 初始化认证系统
    init_auth_system

    log_info "API网关初始化完成"
    return 0
}

# 加载路由配置
load_routes_config() {
    local routes_file="/opt/Z-Panel-Pro/config/routes.conf"

    if [[ -f "${routes_file}" ]]; then
        while IFS='=' read -r path handler; do
            if [[ -n "${path}" ]] && [[ -n "${handler}" ]] && [[ "${path}" != \#* ]]; then
                API_ROUTES["${path}"]="${handler}"
                log_debug "加载路由: ${path} -> ${handler}"
            fi
        done < "${routes_file}"
    fi
}

# 初始化限流
init_rate_limit() {
    log_debug "初始化限流系统..."

    # 清理旧的限流状态
    rm -f /opt/Z-Panel-Pro/tmp/rate_limit/*.state 2>/dev/null || true
}

# 初始化认证系统
init_auth_system() {
    log_debug "初始化认证系统..."

    # 加载用户配置
    local users_file="/opt/Z-Panel-Pro/config/users.conf"

    if [[ ! -f "${users_file}" ]]; then
        # 创建默认用户
        cat > "${users_file}" << 'EOF'
# Z-Panel Pro 用户配置
# 格式: username:sha256_hash
admin:8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918
EOF
    fi
}

# ==============================================================================
# 限流系统
# ==============================================================================
# 检查限流
check_rate_limit() {
    local client_ip="$1"

    if [[ "${API_GATEWAY_CONFIG[rate_limit_enabled]}" != "true" ]]; then
        return 0
    fi

    local state_file="/opt/Z-Panel-Pro/tmp/rate_limit/${client_ip}.state"
    local window="${API_GATEWAY_CONFIG[rate_limit_window]}"
    local max_requests="${API_GATEWAY_CONFIG[rate_limit_requests]}"

    local current_time=$(date +%s)
    local window_start=$((current_time - window))

    # 读取当前状态
    local request_count=0
    local last_reset_time=0

    if [[ -f "${state_file}" ]]; then
        local state=$(cat "${state_file}")
        request_count=$(echo "${state}" | cut -d':' -f1)
        last_reset_time=$(echo "${state}" | cut -d':' -f2)

        # 检查是否需要重置窗口
        if [[ ${last_reset_time} -lt ${window_start} ]]; then
            request_count=0
            last_reset_time=${current_time}
        fi
    fi

    # 检查是否超过限制
    if [[ ${request_count} -ge ${max_requests} ]]; then
        log_warning "限流触发: ${client_ip} (${request_count}/${max_requests})"
        return 1
    fi

    # 更新计数
    ((request_count++))
    echo "${request_count}:${current_time}" > "${state_file}"

    return 0
}

# 清理过期限流状态
cleanup_rate_limit() {
    local window="${API_GATEWAY_CONFIG[rate_limit_window]}"
    local current_time=$(date +%s)
    local window_start=$((current_time - window))

    for state_file in /opt/Z-Panel-Pro/tmp/rate_limit/*.state; do
        if [[ -f "${state_file}" ]]; then
            local last_reset=$(cat "${state_file}" | cut -d':' -f2)

            if [[ ${last_reset} -lt ${window_start} ]]; then
                rm -f "${state_file}"
            fi
        fi
    done
}

# ==============================================================================
# 认证系统
# ==============================================================================
# 验证用户凭证
verify_credentials() {
    local username="$1"
    local password="$2"

    local users_file="/opt/Z-Panel-Pro/config/users.conf"

    if [[ -f "${users_file}" ]]; then
        local stored_hash=$(grep "^${username}:" "${users_file}" | cut -d':' -f2)

        if [[ -n "${stored_hash}" ]]; then
            local computed_hash=$(echo -n "${password}" | sha256sum | cut -d' ' -f1)

            if [[ "${stored_hash}" == "${computed_hash}" ]]; then
                return 0
            fi
        fi
    fi

    return 1
}

# 生成访问令牌
generate_access_token() {
    local username="$1"

    local token=$(head -c 32 /dev/urandom | xxd -p)
    local expires=$(($(date +%s) + 3600))  # 1小时过期

    AUTH_TOKENS["${token}"]="${username}:${expires}"

    # 保存到文件
    echo "${username}:${expires}" > "/opt/Z-Panel-Pro/tmp/sessions/${token}"

    echo "${token}"
}

# 生成刷新令牌
generate_refresh_token() {
    local username="$1"
    local access_token="$2"

    local refresh_token=$(head -c 32 /dev/urandom | xxd -p)
    local expires=$(($(date +%s) + 86400))  # 24小时过期

    AUTH_REFRESH_TOKENS["${refresh_token}"]="${access_token}:${expires}"

    echo "${refresh_token}"
}

# 验证访问令牌
verify_access_token() {
    local token="$1"

    local session_file="/opt/Z-Panel-Pro/tmp/sessions/${token}"

    if [[ -f "${session_file}" ]]; then
        local session_data=$(cat "${session_file}")
        local username=$(echo "${session_data}" | cut -d':' -f1)
        local expires=$(echo "${session_data}" | cut -d':' -f2)
        local current_time=$(date +%s)

        if [[ ${current_time} -lt ${expires} ]]; then
            echo "${username}"
            return 0
        else
            rm -f "${session_file}"
        fi
    fi

    return 1
}

# 刷新令牌
refresh_access_token() {
    local refresh_token="$1"

    local stored_data="${AUTH_REFRESH_TOKENS[${refresh_token}]}"

    if [[ -n "${stored_data}" ]]; then
        local access_token=$(echo "${stored_data}" | cut -d':' -f1)
        local expires=$(echo "${stored_data}" | cut -d':' -f2)
        local current_time=$(date +%s)

        if [[ ${current_time} -lt ${expires} ]]; then
            local session_file="/opt/Z-Panel-Pro/tmp/sessions/${access_token}"
            local username=$(cat "${session_file}" | cut -d':' -f1)

            # 生成新令牌
            local new_token=$(generate_access_token "${username}")
            local new_refresh_token=$(generate_refresh_token "${username}" "${new_token}")

            # 删除旧令牌
            rm -f "/opt/Z-Panel-Pro/tmp/sessions/${access_token}"
            unset AUTH_REFRESH_TOKENS["${refresh_token}"]

            echo "{\"access_token\":\"${new_token}\",\"refresh_token\":\"${new_refresh_token}\"}"
            return 0
        fi
    fi

    return 1
}

# 注销
logout() {
    local token="$1"

    rm -f "/opt/Z-Panel-Pro/tmp/sessions/${token}"

    # 查找并删除关联的刷新令牌
    for rt in "${!AUTH_REFRESH_TOKENS[@]}"; do
        local at=$(echo "${AUTH_REFRESH_TOKENS[${rt}]}" | cut -d':' -f1)
        if [[ "${at}" == "${token}" ]]; then
            unset AUTH_REFRESH_TOKENS["${rt}"]
            break
        fi
    done

    return 0
}

# ==============================================================================
# 路由处理
# ==============================================================================
# 查找路由
find_route() {
    local path="$1"

    # 精确匹配
    if [[ -n "${API_ROUTES[${path}]+isset}" ]]; then
        echo "${API_ROUTES[${path}]}"
        return 0
    fi

    # 模糊匹配（支持路径参数）
    for route in "${!API_ROUTES[@]}"; do
        if [[ "${route}" == *"{*}"* ]]; then
            local pattern="${route}"
            pattern=$(echo "${pattern}" | sed 's/{[^}]*}/[^\/]*/g')

            if [[ "${path}" =~ ^${pattern}$ ]]; then
                echo "${API_ROUTES[${route}]}"
                return 0
            fi
        fi
    done

    return 1
}

# 路由请求
route_request() {
    local method="$1"
    local path="$2"
    local headers="$3"
    local body="$4"

    log_debug "路由请求: ${method} ${path}"

    # 检查认证
    if [[ "${API_GATEWAY_CONFIG[auth_enabled]}" == "true" ]]; then
        local auth_result=$(check_authentication "${headers}")

        if [[ "${auth_result}" != "ok" ]]; then
            build_error_response 401 "Unauthorized"
            return 1
        fi
    fi

    # 查找路由
    local handler=$(find_route "${path}")

    if [[ -n "${handler}" ]]; then
        # 调用处理器
        ${handler} "${method}" "${path}" "${headers}" "${body}"
    else
        build_error_response 404 "Not Found"
        return 1
    fi
}

# 检查认证
check_authentication() {
    local headers="$1"

    # 检查Bearer Token
    local auth_header=$(echo "${headers}" | grep -i "Authorization:" | head -n 1)

    if [[ -n "${auth_header}" ]]; then
        local auth_value=$(echo "${auth_header}" | cut -d' ' -f2-)

        if [[ "${auth_value}" == "Bearer "* ]]; then
            local token="${auth_value#Bearer }"

            if verify_access_token "${token}" > /dev/null; then
                echo "ok"
                return 0
            fi
        fi
    fi

    # 检查Session Token
    local session_header=$(echo "${headers}" | grep -i "X-Session-Token:" | head -n 1)

    if [[ -n "${session_header}" ]]; then
        local token=$(echo "${session_header}" | cut -d' ' -f2)

        if verify_access_token "${token}" > /dev/null; then
            echo "ok"
            return 0
        fi
    fi

    echo "unauthorized"
    return 1
}

# ==============================================================================
# 认证处理器
# ==============================================================================
handle_login() {
    local method="$1"
    local path="$2"
    local headers="$3"
    local body="$4"

    local username=$(echo "${body}" | jq -r '.username' 2>/dev/null)
    local password=$(echo "${body}" | jq -r '.password' 2>/dev/null)

    if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
        build_error_response 400 "Missing username or password"
        return 1
    fi

    if verify_credentials "${username}" "${password}"; then
        local access_token=$(generate_access_token "${username}")
        local refresh_token=$(generate_refresh_token "${username}" "${access_token}")

        local response=$(cat <<EOF
{
    "status": "success",
    "data": {
        "access_token": "${access_token}",
        "refresh_token": "${refresh_token}",
        "token_type": "Bearer",
        "expires_in": 3600
    }
}
EOF
)
        build_success_response 200 "${response}"
    else
        build_error_response 401 "Invalid credentials"
        return 1
    fi
}

handle_logout() {
    local method="$1"
    local path="$2"
    local headers="$3"
    local body="$4"

    local auth_header=$(echo "${headers}" | grep -i "Authorization:" | head -n 1)
    local token="${auth_header#Bearer }"

    if [[ -n "${token}" ]] && [[ "${token}" != "${auth_header}" ]]; then
        logout "${token}"
    fi

    local response='{"status": "success", "message": "Logged out successfully"}'
    build_success_response 200 "${response}"
}

handle_refresh_token() {
    local method="$1"
    local path="$2"
    local headers="$3"
    local body="$4"

    local refresh_token=$(echo "${body}" | jq -r '.refresh_token' 2>/dev/null)

    if [[ -z "${refresh_token}" ]]; then
        build_error_response 400 "Missing refresh_token"
        return 1
    fi

    local new_tokens=$(refresh_access_token "${refresh_token}")

    if [[ $? -eq 0 ]]; then
        local response=$(cat <<EOF
{
    "status": "success",
    "data": ${new_tokens}
}
EOF
)
        build_success_response 200 "${response}"
    else
        build_error_response 401 "Invalid refresh_token"
        return 1
    fi
}

# ==============================================================================
# 响应构建
# ==============================================================================
# 构建成功响应
build_success_response() {
    local status_code="$1"
    local body="$2"
    local extra_headers="$3"

    local response="HTTP/1.1 ${status_code} OK"$'\n'
    response+="Content-Type: application/json"$'\n'
    response+="Content-Length: ${#body}"$'\n'
    response+="X-Powered-By: Z-Panel-Pro/8.0"$'\n'

    # 添加CORS头部
    if [[ "${API_GATEWAY_CONFIG[cors_enabled]}" == "true" ]]; then
        response+="Access-Control-Allow-Origin: ${API_GATEWAY_CONFIG[cors_origin]}"$'\n'
        response+="Access-Control-Allow-Methods: ${API_GATEWAY_CONFIG[cors_methods]}"$'\n'
        response+="Access-Control-Allow-Headers: ${API_GATEWAY_CONFIG[cors_headers]}"$'\n'
    fi

    if [[ -n "${extra_headers}" ]]; then
        response+="${extra_headers}"$'\n'
    fi

    response+=$'\n'
    response+="${body}"

    echo "${response}"
}

# 构建错误响应
build_error_response() {
    local status_code="$1"
    local message="$2"

    local body=$(cat <<EOF
{
    "status": "error",
    "error": {
        "code": ${status_code},
        "message": "${message}"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

    build_success_response "${status_code}" "${body}"
}

# 处理OPTIONS请求（CORS预检）
handle_options_request() {
    local response="HTTP/1.1 204 No Content"$'\n'
    response+="Content-Length: 0"$'\n'
    response+="Access-Control-Allow-Origin: ${API_GATEWAY_CONFIG[cors_origin]}"$'\n'
    response+="Access-Control-Allow-Methods: ${API_GATEWAY_CONFIG[cors_methods]}"$'\n'
    response+="Access-Control-Allow-Headers: ${API_GATEWAY_CONFIG[cors_headers]}"$'\n'
    response+="Access-Control-Max-Age: 86400"$'\n'
    response+=$'\n'

    echo "${response}"
}

# ==============================================================================
# 请求处理
# ==============================================================================
# 处理HTTP请求
handle_http_request() {
    local request="$1"
    local client_ip="$2"

    # 解析请求
    local first_line=$(echo "${request}" | head -n 1)
    local method=$(echo "${first_line}" | cut -d' ' -f1)
    local path=$(echo "${first_line}" | cut -d' ' -f2)

    # 提取头部
    local headers=""
    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            break
        fi
        headers+="${line}"$'\n'
    done <<< "${request}"

    # 提取body
    local body="${request#*$'\n'$'\n'}"

    # 记录请求
    if [[ "${API_GATEWAY_CONFIG[log_requests]}" == "true" ]]; then
        log_request "${method}" "${path}" "${client_ip}"
    fi

    # 检查限流
    if ! check_rate_limit "${client_ip}"; then
        build_error_response 429 "Too Many Requests"
        return 1
    fi

    # 处理OPTIONS请求
    if [[ "${method}" == "OPTIONS" ]]; then
        handle_options_request
        return 0
    fi

    # 路由请求
    route_request "${method}" "${path}" "${headers}" "${body}"
}

# 记录请求
log_request() {
    local method="$1"
    local path="$2"
    local client_ip="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] ${client_ip} ${method} ${path}" >> "/opt/Z-Panel-Pro/logs/api/access.log"
}

# ==============================================================================
# 启动API网关
# ==============================================================================
# 启动API网关服务器
start_api_gateway() {
    log_info "启动API网关..."

    # 初始化
    init_api_gateway

    local host="${API_GATEWAY_CONFIG[host]}"
    local port="${API_GATEWAY_CONFIG[port]}"

    log_info "API网关监听: ${host}:${port}"

    # 使用socat启动服务器
    if command -v socat &> /dev/null; then
        socat TCP-LISTEN:${port},fork,reuseaddr EXEC:"/opt/Z-Panel-Pro/lib/api_gateway.sh handle_connection" &
        API_GATEWAY_PID=$!
    else
        log_error "需要socat来启动API网关"
        return 1
    fi

    API_GATEWAY_RUNNING=true

    # 启动清理任务
    start_cleanup_tasks &

    log_info "API网关启动完成 (PID: ${API_GATEWAY_PID})"
    return 0
}

# 停止API网关
stop_api_gateway() {
    log_info "停止API网关..."

    if [[ -n "${API_GATEWAY_PID}" ]] && kill -0 ${API_GATEWAY_PID} 2>/dev/null; then
        kill ${API_GATEWAY_PID}
        wait ${API_GATEWAY_PID} 2>/dev/null
    fi

    API_GATEWAY_RUNNING=false
    API_GATEWAY_PID=""

    log_info "API网关已停止"
    return 0
}

# 处理连接（通过socat调用）
handle_connection() {
    local request=$(cat)
    local client_ip=$(echo "${request}" | grep -i "X-Real-IP:" | head -n 1 | cut -d' ' -f2)

    if [[ -z "${client_ip}" ]]; then
        client_ip="unknown"
    fi

    handle_http_request "${request}" "${client_ip}"
}

# 启动清理任务
start_cleanup_tasks() {
    while [[ "${API_GATEWAY_RUNNING}" == "true" ]]; do
        sleep 300  # 每5分钟清理一次

        # 清理限流状态
        cleanup_rate_limit

        # 清理过期session
        cleanup_expired_sessions
    done
}

# 清理过期session
cleanup_expired_sessions() {
    local current_time=$(date +%s)

    for session_file in /opt/Z-Panel-Pro/tmp/sessions/*; do
        if [[ -f "${session_file}" ]]; then
            local expires=$(cat "${session_file}" | cut -d':' -f2)

            if [[ ${current_time} -gt ${expires} ]]; then
                rm -f "${session_file}"
            fi
        fi
    done
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_api_gateway
export -f load_routes_config
export -f init_rate_limit
export -f init_auth_system
export -f check_rate_limit
export -f cleanup_rate_limit
export -f verify_credentials
export -f generate_access_token
export -f generate_refresh_token
export -f verify_access_token
export -f refresh_access_token
export -f logout
export -f find_route
export -f route_request
export -f check_authentication
export -f handle_login
export -f handle_logout
export -f handle_refresh_token
export -f build_success_response
export -f build_error_response
export -f handle_options_request
export -f handle_http_request
export -f log_request
export -f start_api_gateway
export -f stop_api_gateway
export -f handle_connection
export -f start_cleanup_tasks
export -f cleanup_expired_sessions
