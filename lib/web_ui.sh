#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - Web UI框架
# ==============================================================================
# @description    基于WebSocket的实时Web用户界面框架
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# Web UI配置
# ==============================================================================
declare -gA WEB_UI_CONFIG=(
    [host]="0.0.0.0"
    [port]="8080"
    [ssl_enabled]="false"
    [ssl_cert]=""
    [ssl_key]=""
    [static_dir]="/opt/Z-Panel-Pro/web/static"
    [templates_dir]="/opt/Z-Panel-Pro/web/templates"
    [websocket_enabled]="true"
    [websocket_path]="/ws"
    [auth_enabled]="true"
    [session_timeout]="3600"
)

# ==============================================================================
# Web UI状态
# ==============================================================================
declare -g WEB_UI_RUNNING=false
declare -g WEB_UI_PID=""
declare -gA WEB_UI_SESSIONS=()
declare -gA WEBSOCKET_CONNECTIONS=()

# ==============================================================================
# HTTP状态码
# ==============================================================================
declare -gA HTTP_STATUS=(
    [200]="OK"
    [201]="Created"
    [204]="No Content"
    [301]="Moved Permanently"
    [302]="Found"
    [400]="Bad Request"
    [401]="Unauthorized"
    [403]="Forbidden"
    [404]="Not Found"
    [405]="Method Not Allowed"
    [429]="Too Many Requests"
    [500]="Internal Server Error"
    [503]="Service Unavailable"
)

# ==============================================================================
# MIME类型
# ==============================================================================
declare -gA MIME_TYPES=(
    [html]="text/html"
    [css]="text/css"
    [js]="application/javascript"
    [json]="application/json"
    [png]="image/png"
    [jpg]="image/jpeg"
    [gif]="image/gif"
    [svg]="image/svg+xml"
    [ico]="image/x-icon"
    [woff]="font/woff"
    [woff2]="font/woff2"
    [ttf]="font/ttf"
    [txt]="text/plain"
    [pdf]="application/pdf"
)

# ==============================================================================
# HTTP请求解析
# ==============================================================================
parse_http_request() {
    local request="$1"

    # 解析请求行
    local first_line=$(echo "${request}" | head -n 1)
    local method=$(echo "${first_line}" | cut -d' ' -f1)
    local path=$(echo "${first_line}" | cut -d' ' -f2)
    local version=$(echo "${first_line}" | cut -d' ' -f3)

    # 解析头部
    local headers=""
    local body=""
    local in_body=false

    while IFS= read -r line; do
        if [[ "${in_body}" == "true" ]]; then
            body+="${line}"$'\n'
        elif [[ -z "${line}" ]]; then
            in_body=true
        else
            headers+="${line}"$'\n'
        fi
    done <<< "${request}"

    # 解析查询参数
    local query_params=""
    local query_string=""
    if [[ "${path}" == *"?"* ]]; then
        query_string="${path#*\?}"
        path="${path%%\?*}"

        # 解析查询参数
        IFS='&' read -ra PARAMS <<< "${query_string}"
        for param in "${PARAMS[@]}"; do
            local key="${param%%=*}"
            local value="${param#*=}"
            query_params+="${key}=${value}"$'\n'
        done
    fi

    # 返回解析结果
    cat <<EOF
method=${method}
path=${path}
version=${version}
query_string=${query_string}
query_params=${query_params}
headers=${headers}
body=${body}
EOF
}

# ==============================================================================
# HTTP响应生成
# ==============================================================================
build_http_response() {
    local status_code="$1"
    local content_type="$2"
    local body="$3"
    local headers="$4"

    local status_line="HTTP/1.1 ${status_code} ${HTTP_STATUS[${status_code}]}"
    local response="${status_line}"$'\n'

    # 添加默认头部
    response+="Content-Type: ${content_type}"$'\n'
    response+="Content-Length: ${#body}"$'\n'
    response+="Server: Z-Panel-Pro/8.0"$'\n'
    response+="X-Powered-By: Z-Panel-Pro Enterprise"$'\n'

    # 添加自定义头部
    if [[ -n "${headers}" ]]; then
        response+="${headers}"$'\n'
    fi

    response+=$'\n'  # 空行分隔头部和body
    response+="${body}"

    echo "${response}"
}

# ==============================================================================
# 路由处理
# ==============================================================================
declare -gA HTTP_ROUTES=()

# 注册路由
register_route() {
    local method="$1"
    local path="$2"
    local handler="$3"

    local route_key="${method}:${path}"
    HTTP_ROUTES["${route_key}"]="${handler}"

    log_debug "注册路由: ${method} ${path} -> ${handler}"
}

# 查找路由
find_route() {
    local method="$1"
    local path="$2"

    # 精确匹配
    local route_key="${method}:${path}"
    if [[ -n "${HTTP_ROUTES[${route_key}]+isset}" ]]; then
        echo "${HTTP_ROUTES[${route_key}]}"
        return 0
    fi

    # 路径参数匹配
    for route in "${!HTTP_ROUTES[@]}"; do
        local route_method="${route%%:*}"
        local route_path="${route#*:}"

        if [[ "${route_method}" == "${method}" ]]; then
            # 检查是否是路径参数路由
            if [[ "${route_path}" == *"{*}"* ]]; then
                local pattern="${route_path}"
                pattern=$(echo "${pattern}" | sed 's/{[^}]*}/[^\/]*/g')

                if [[ "${path}" =~ ^${pattern}$ ]]; then
                    echo "${HTTP_ROUTES[${route}]}"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# 处理HTTP请求
handle_http_request() {
    local request="$1"
    local client_fd="$2"

    # 解析请求
    local parsed=$(parse_http_request "${request}")
    local method=$(echo "${parsed}" | grep "^method=" | cut -d'=' -f2)
    local path=$(echo "${parsed}" | grep "^path=" | cut -d'=' -f2)
    local query_string=$(echo "${parsed}" | grep "^query_string=" | cut -d'=' -f2)
    local body=$(echo "${parsed}" | grep "^body=" | cut -d'=' -f2-)

    log_debug "HTTP请求: ${method} ${path}"

    # 检查认证
    if [[ "${WEB_UI_CONFIG[auth_enabled]}" == "true" ]]; then
        local auth_result=$(check_authentication "${parsed}")
        if [[ "${auth_result}" != "ok" ]]; then
            local response=$(build_http_response 401 "application/json" '{"error":"Unauthorized"}' "WWW-Authenticate: Basic realm=\"Z-Panel Pro\"")
            echo "${response}" >&${client_fd}
            return 1
        fi
    fi

    # 查找路由处理器
    local handler=$(find_route "${method}" "${path}")

    if [[ -n "${handler}" ]]; then
        # 调用处理器
        local response=$(${handler} "${method}" "${path}" "${query_string}" "${body}")
        echo "${response}" >&${client_fd}
    else
        # 静态文件服务
        if [[ "${path}" == "/" ]]; then
            path="/index.html"
        fi

        local static_file="${WEB_UI_CONFIG[static_dir]}${path}"

        if [[ -f "${static_file}" ]]; then
            local ext="${static_file##*.}"
            local content_type="${MIME_TYPES[${ext}]:-application/octet-stream}"
            local file_content=$(cat "${static_file}")
            local response=$(build_http_response 200 "${content_type}" "${file_content}")
            echo "${response}" >&${client_fd}
        else
            # 404 Not Found
            local response=$(build_http_response 404 "application/json" '{"error":"Not Found"}')
            echo "${response}" >&${client_fd}
        fi
    fi
}

# ==============================================================================
# 认证系统
# ==============================================================================
# 检查认证
check_authentication() {
    local parsed="$1"
    local headers=$(echo "${parsed}" | grep "^headers=" -A 20)

    # 检查Basic Auth
    local auth_header=$(echo "${headers}" | grep -i "Authorization:" | head -n 1)

    if [[ -n "${auth_header}" ]]; then
        local auth_value=$(echo "${auth_header}" | cut -d' ' -f2-)

        if [[ "${auth_value}" == "Basic "* ]]; then
            local credentials=$(echo "${auth_value#Basic }" | base64 -d 2>/dev/null)
            local username="${credentials%%:*}"
            local password="${credentials#*:}"

            # 验证用户名密码
            if validate_user "${username}" "${password}"; then
                echo "ok"
                return 0
            fi
        fi
    fi

    # 检查Session Token
    local session_header=$(echo "${headers}" | grep -i "X-Session-Token:" | head -n 1)

    if [[ -n "${session_header}" ]]; then
        local token=$(echo "${session_header}" | cut -d' ' -f2)

        if validate_session_token "${token}"; then
            echo "ok"
            return 0
        fi
    fi

    echo "unauthorized"
    return 1
}

# 验证用户
validate_user() {
    local username="$1"
    local password="$2"

    # 这里应该从配置或数据库读取用户信息
    # 简化实现：使用配置文件
    local config_file="/opt/Z-Panel-Pro/config/users.conf"

    if [[ -f "${config_file}" ]]; then
        local stored_hash=$(grep "^${username}:" "${config_file}" | cut -d':' -f2)

        if [[ -n "${stored_hash}" ]]; then
            local computed_hash=$(echo -n "${password}" | sha256sum | cut -d' ' -f1)

            if [[ "${stored_hash}" == "${computed_hash}" ]]; then
                return 0
            fi
        fi
    fi

    return 1
}

# 验证Session Token
validate_session_token() {
    local token="$1"

    local session_file="/opt/Z-Panel-Pro/tmp/sessions/${token}"

    if [[ -f "${session_file}" ]]; then
        local session_data=$(cat "${session_file}")
        local session_time=$(echo "${session_data}" | cut -d':' -f1)
        local current_time=$(date +%s)

        # 检查session是否过期
        local timeout="${WEB_UI_CONFIG[session_timeout]}"

        if [[ $((current_time - session_time)) -lt ${timeout} ]]; then
            # 更新session时间
            echo "${current_time}:${username}" > "${session_file}"
            return 0
        else
            rm -f "${session_file}"
        fi
    fi

    return 1
}

# 创建Session Token
create_session_token() {
    local username="$1"

    local token=$(head -c 32 /dev/urandom | xxd -p)
    local session_time=$(date +%s)
    local session_dir="/opt/Z-Panel-Pro/tmp/sessions"

    mkdir -p "${session_dir}"
    echo "${session_time}:${username}" > "${session_dir}/${token}"

    echo "${token}"
}

# ==============================================================================
# WebSocket处理
# ==============================================================================
# WebSocket握手
websocket_handshake() {
    local request="$1"
    local client_fd="$2"

    # 提取WebSocket Key
    local ws_key=$(echo "${request}" | grep -i "Sec-WebSocket-Key:" | cut -d' ' -f2 | tr -d '\r')

    if [[ -z "${ws_key}" ]]; then
        local response=$(build_http_response 400 "application/json" '{"error":"Bad Request"}')
        echo "${response}" >&${client_fd}
        return 1
    fi

    # 生成WebSocket Accept
    local ws_accept=$(echo -n "${ws_key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11" | sha1sum | xxd -r -p | base64)

    # 构建握手响应
    local response="HTTP/1.1 101 Switching Protocols"$'\n'
    response+="Upgrade: websocket"$'\n'
    response+="Connection: Upgrade"$'\n'
    response+="Sec-WebSocket-Accept: ${ws_accept}"$'\n'
    response+=$'\n'

    echo "${response}" >&${client_fd}

    # 记录连接
    local connection_id="${client_fd}"
    WEBSOCKET_CONNECTIONS["${connection_id}"]="${client_fd}"

    log_debug "WebSocket连接建立: ${connection_id}"

    # 启动消息处理
    handle_websocket_messages "${client_fd}" &

    return 0
}

# 处理WebSocket消息
handle_websocket_messages() {
    local client_fd="$1"
    local connection_id="${client_fd}"

    while true; do
        # 读取消息帧
        local frame=$(read_websocket_frame "${client_fd}")

        if [[ -z "${frame}" ]]; then
            break
        fi

        # 解析消息
        local opcode=$(echo "${frame}" | cut -d':' -f1)
        local payload=$(echo "${frame}" | cut -d':' -f2-)

        case "${opcode}" in
            1)  # Text message
                handle_websocket_text "${connection_id}" "${payload}"
                ;;
            2)  # Binary message
                handle_websocket_binary "${connection_id}" "${payload}"
                ;;
            8)  # Close
                close_websocket_connection "${connection_id}"
                break
                ;;
            9)  # Ping
                send_websocket_pong "${client_fd}"
                ;;
            10) # Pong
                # 忽略pong
                ;;
        esac
    done
}

# 读取WebSocket帧
read_websocket_frame() {
    local client_fd="$1"

    # 读取前2字节
    local header=$(dd if=/proc/self/fd/${client_fd} bs=1 count=2 2>/dev/null | xxd -p)

    if [[ -z "${header}" ]]; then
        return 1
    fi

    local byte1=$((16#${header:0:2}))
    local byte2=$((16#${header:2:2}))

    local fin=$(( (byte1 & 0x80) >> 7 ))
    local opcode=$(( byte1 & 0x0F ))
    local masked=$(( (byte2 & 0x80) >> 7 ))
    local payload_len=$(( byte2 & 0x7F ))

    # 读取扩展长度
    local extended_len=""
    if [[ ${payload_len} -eq 126 ]]; then
        extended_len=$(dd if=/proc/self/fd/${client_fd} bs=1 count=2 2>/dev/null | xxd -p -e)
        payload_len=$((16#${extended_len}))
    elif [[ ${payload_len} -eq 127 ]]; then
        extended_len=$(dd if=/proc/self/fd/${client_fd} bs=1 count=8 2>/dev/null | xxd -p -e)
        payload_len=$((16#${extended_len}))
    fi

    # 读取掩码键
    local mask_key=""
    if [[ ${masked} -eq 1 ]]; then
        mask_key=$(dd if=/proc/self/fd/${client_fd} bs=1 count=4 2>/dev/null | xxd -p)
    fi

    # 读取payload
    local payload=$(dd if=/proc/self/fd/${client_fd} bs=1 count=${payload_len} 2>/dev/null)

    # 解码payload
    if [[ ${masked} -eq 1 ]]; then
        local decoded_payload=""
        for ((i=0; i<${payload_len}; i++)); do
            local byte=$(echo -n "${payload}" | dd bs=1 count=1 skip=${i} 2>/dev/null | xxd -p)
            local mask_byte="${mask_key:$((i % 8)):2}"
            local unmasked_byte=$((16#${byte} ^ 16#${mask_byte}))
            decoded_payload+=$(printf "\\x%02x" ${unmasked_byte})
        done
        payload=$(echo -e "${decoded_payload}")
    fi

    echo "${opcode}:${payload}"
}

# 发送WebSocket帧
send_websocket_frame() {
    local client_fd="$1"
    local opcode="$2"
    local payload="$3"

    local payload_len=${#payload}
    local frame=""

    # 构建帧头
    local byte1=$((0x80 | opcode))  # FIN=1
    frame+=$(printf "\\x%02x" ${byte1})

    # 构建payload长度
    if [[ ${payload_len} -lt 126 ]]; then
        frame+=$(printf "\\x%02x" ${payload_len})
    elif [[ ${payload_len} -lt 65536 ]]; then
        frame+=$(printf "\\x%02x" 126)
        frame+=$(printf "\\x%02x\\x%02x" $((payload_len >> 8)) $((payload_len & 0xFF)))
    else
        frame+=$(printf "\\x%02x" 127)
        for ((i=7; i>=0; i--)); do
            frame+=$(printf "\\x%02x" $((payload_len >> (i * 8)) & 0xFF))
        done
    fi

    # 添加payload
    frame+="${payload}"

    # 发送帧
    echo -n "${frame}" >&${client_fd}
}

# 处理文本消息
handle_websocket_text() {
    local connection_id="$1"
    local payload="$2"

    log_debug "WebSocket文本消息: ${connection_id} - ${payload}"

    # 解析JSON消息
    local message_type=$(echo "${payload}" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)

    case "${message_type}" in
        subscribe)
            local channel=$(echo "${payload}" | grep -o '"channel":"[^"]*"' | cut -d'"' -f4)
            subscribe_to_channel "${connection_id}" "${channel}"
            ;;
        unsubscribe)
            local channel=$(echo "${payload}" | grep -o '"channel":"[^"]*"' | cut -d'"' -f4)
            unsubscribe_from_channel "${connection_id}" "${channel}"
            ;;
        command)
            local command=$(echo "${payload}" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
            local params=$(echo "${payload}" | grep -o '"params":{[^}]*}' | cut -d'{' -f2 | cut -d'}' -f1)
            execute_websocket_command "${connection_id}" "${command}" "${params}"
            ;;
    esac
}

# 发送Pong
send_websocket_pong() {
    local client_fd="$1"
    send_websocket_frame "${client_fd}" 10 ""
}

# 关闭WebSocket连接
close_websocket_connection() {
    local connection_id="$1"
    local client_fd="${WEBSOCKET_CONNECTIONS[${connection_id}]}"

    # 发送关闭帧
    send_websocket_frame "${client_fd}" 8 ""

    # 关闭连接
    exec {client_fd}>&-

    # 从连接列表移除
    unset WEBSOCKET_CONNECTIONS["${connection_id}"]

    log_debug "WebSocket连接关闭: ${connection_id}"
}

# ==============================================================================
# 广播系统
# ==============================================================================
declare -gA WEBSOCKET_CHANNELS=()

# 订阅频道
subscribe_to_channel() {
    local connection_id="$1"
    local channel="$2"

    if [[ -z "${WEBSOCKET_CHANNELS[${channel}]}" ]]; then
        WEBSOCKET_CHANNELS["${channel}"]="${connection_id}"
    else
        if [[ "${WEBSOCKET_CHANNELS[${channel}]}" != *"${connection_id}"* ]]; then
            WEBSOCKET_CHANNELS["${channel}"]+=" ${connection_id}"
        fi
    fi

    log_debug "订阅频道: ${connection_id} -> ${channel}"
}

# 取消订阅
unsubscribe_from_channel() {
    local connection_id="$1"
    local channel="$2"

    if [[ -n "${WEBSOCKET_CHANNELS[${channel}]}" ]]; then
        local connections="${WEBSOCKET_CHANNELS[${channel}]}"
        connections="${connections//${connection_id}/}"
        WEBSOCKET_CHANNELS["${channel}"]="${connections}"
    fi

    log_debug "取消订阅: ${connection_id} <- ${channel}"
}

# 广播消息
broadcast_to_channel() {
    local channel="$1"
    local message="$2"

    local connections="${WEBSOCKET_CHANNELS[${channel}]:-}"

    for conn in ${connections}; do
        local client_fd="${WEBSOCKET_CONNECTIONS[${conn}]}"

        if [[ -n "${client_fd}" ]]; then
            send_websocket_frame "${client_fd}" 1 "${message}"
        fi
    done

    log_debug "广播消息: ${channel} -> ${connections}"
}

# 广播系统状态
broadcast_system_status() {
    local status="$1"

    local message="{\"type\":\"status\",\"data\":${status}}"
    broadcast_to_channel "status" "${message}"
}

# ==============================================================================
# REST API端点
# ==============================================================================
# 注册默认API路由
register_default_routes() {
    # 系统信息
    register_route "GET" "/api/v1/system/info" "api_get_system_info"
    register_route "GET" "/api/v1/system/metrics" "api_get_system_metrics"
    register_route "GET" "/api/v1/system/health" "api_get_health_status"

    # 内存管理
    register_route "GET" "/api/v1/memory/info" "api_get_memory_info"
    register_route "GET" "/api/v1/memory/usage" "api_get_memory_usage"
    register_route "POST" "/api/v1/memory/optimize" "api_optimize_memory"

    # ZRAM管理
    register_route "GET" "/api/v1/zram/info" "api_get_zram_info"
    register_route "GET" "/api/v1/zram/usage" "api_get_zram_usage"
    register_route "POST" "/api/v1/zram/start" "api_start_zram"
    register_route "POST" "/api/v1/zram/stop" "api_stop_zram"
    register_route "POST" "/api/v1/zram/resize" "api_resize_zram"

    # 决策引擎
    register_route "GET" "/api/v1/decision_engine/status" "api_get_decision_status"
    register_route "GET" "/api/v1/decision_engine/decisions" "api_get_decisions"
    register_route "POST" "/api/v1/decision_engine/start" "api_start_decision_engine"
    register_route "POST" "/api/v1/decision_engine/stop" "api_stop_decision_engine"

    # 配置
    register_route "GET" "/api/v1/config" "api_get_config"
    register_route "PUT" "/api/v1/config" "api_update_config"

    # 认证
    register_route "POST" "/api/v1/auth/login" "api_login"
    register_route "POST" "/api/v1/auth/logout" "api_logout"
}

# API处理器
api_get_system_info() {
    local method="$1"
    local path="$2"

    local info=$(get_system_info)
    local response=$(build_http_response 200 "application/json" "${info}")
    echo "${response}"
}

api_get_system_metrics() {
    local method="$1"
    local path="$2"

    local metrics=$(get_system_metrics)
    local response=$(build_http_response 200 "application/json" "${metrics}")
    echo "${response}"
}

api_get_health_status() {
    local method="$1"
    local path="$2"

    local health=$(get_health_status)
    local response=$(build_http_response 200 "application/json" "${health}")
    echo "${response}"
}

api_get_memory_info() {
    local method="$1"
    local path="$2"

    local mem_info=$(get_memory_info false)
    local response=$(build_http_response 200 "application/json" "${mem_info}")
    echo "${response}"
}

api_get_memory_usage() {
    local method="$1"
    local path="$2"
    local query_string="$3"

    local format="json"
    if [[ "${query_string}" == *"format=plain"* ]]; then
        format="plain"
    fi

    local mem_usage=$(get_memory_usage "${format}")
    local response=$(build_http_response 200 "application/json" "${mem_usage}")
    echo "${response}"
}

api_optimize_memory() {
    local method="$1"
    local path="$2"
    local body="$3"

    local level="normal"
    if [[ "${body}" == *"level=aggressive"* ]]; then
        level="aggressive"
    fi

    optimize_memory "${level}"

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"Memory optimization started"}')
    echo "${response}"
}

api_get_zram_info() {
    local method="$1"
    local path="$2"

    local zram_info=$(get_zram_info)
    local response=$(build_http_response 200 "application/json" "${zram_info}")
    echo "${response}"
}

api_get_zram_usage() {
    local method="$1"
    local path="$2"

    local zram_usage=$(get_zram_usage)
    local response=$(build_http_response 200 "application/json" "${zram_usage}")
    echo "${response}"
}

api_start_zram() {
    local method="$1"
    local path="$2"

    start_zram

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"ZRAM started"}')
    echo "${response}"
}

api_stop_zram() {
    local method="$1"
    local path="$2"

    stop_zram

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"ZRAM stopped"}')
    echo "${response}"
}

api_resize_zram() {
    local method="$1"
    local path="$2"
    local body="$3"

    local size=$(echo "${body}" | grep -o '"size":[0-9]*' | cut -d':' -f2)

    if [[ -n "${size}" ]]; then
        resize_zram "${size}"
    fi

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"ZRAM resized"}')
    echo "${response}"
}

api_get_decision_status() {
    local method="$1"
    local path="$2"

    local status=$(get_decision_engine_status)
    local response=$(build_http_response 200 "application/json" "${status}")
    echo "${response}"
}

api_get_decisions() {
    local method="$1"
    local path="$2"
    local query_string="$3"

    local limit="10"
    if [[ "${query_string}" == *"limit="* ]]; then
        limit=$(echo "${query_string}" | grep -o "limit=[0-9]*" | cut -d'=' -f2)
    fi

    local decisions=$(get_recent_decisions "${limit}")
    local response=$(build_http_response 200 "application/json" "${decisions}")
    echo "${response}"
}

api_start_decision_engine() {
    local method="$1"
    local path="$2"

    start_decision_engine

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"Decision engine started"}')
    echo "${response}"
}

api_stop_decision_engine() {
    local method="$1"
    local path="$2"

    stop_decision_engine

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"Decision engine stopped"}')
    echo "${response}"
}

api_get_config() {
    local method="$1"
    local path="$2"

    local config=$(get_config_json)
    local response=$(build_http_response 200 "application/json" "${config}")
    echo "${response}"
}

api_update_config() {
    local method="$1"
    local path="$2"
    local body="$3"

    update_config_from_json "${body}"

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"Configuration updated"}')
    echo "${response}"
}

api_login() {
    local method="$1"
    local path="$2"
    local body="$3"

    local username=$(echo "${body}" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    local password=$(echo "${body}" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

    if validate_user "${username}" "${password}"; then
        local token=$(create_session_token "${username}")
        local response=$(build_http_response 200 "application/json" "{\"status\":\"success\",\"token\":\"${token}\"}")
        echo "${response}"
    else
        local response=$(build_http_response 401 "application/json" '{"status":"error","message":"Invalid credentials"}')
        echo "${response}"
    fi
}

api_logout() {
    local method="$1"
    local path="$2"
    local headers="$3"

    local token=$(echo "${headers}" | grep -i "X-Session-Token:" | cut -d' ' -f2)

    if [[ -n "${token}" ]]; then
        rm -f "/opt/Z-Panel-Pro/tmp/sessions/${token}"
    fi

    local response=$(build_http_response 200 "application/json" '{"status":"success","message":"Logged out"}')
    echo "${response}"
}

# ==============================================================================
# Web服务器
# ==============================================================================
# 启动Web服务器
start_web_ui() {
    log_info "启动Web UI服务器..."

    # 初始化目录
    mkdir -p "${WEB_UI_CONFIG[static_dir]}"
    mkdir -p "${WEB_UI_CONFIG[templates_dir]}"
    mkdir -p "/opt/Z-Panel-Pro/tmp/sessions"

    # 注册默认路由
    register_default_routes

    # 启动服务器
    local host="${WEB_UI_CONFIG[host]}"
    local port="${WEB_UI_CONFIG[port]}"

    log_info "Web UI服务器监听: ${host}:${port}"

    # 使用socat或nc启动服务器
    if command -v socat &> /dev/null; then
        socat TCP-LISTEN:${port},fork,reuseaddr EXEC:"/opt/Z-Panel-Pro/lib/web_ui.sh handle_server" &
        WEB_UI_PID=$!
    elif command -v nc &> /dev/null; then
        # 使用nc实现（简化版本）
        while true; do
            nc -l -p ${port} | /opt/Z-Panel-Pro/lib/web_ui.sh handle_server &
        done &
        WEB_UI_PID=$!
    else
        log_error "需要socat或nc来启动Web服务器"
        return 1
    fi

    WEB_UI_RUNNING=true

    # 启动状态广播
    start_status_broadcast &

    log_info "Web UI服务器启动完成 (PID: ${WEB_UI_PID})"
    return 0
}

# 停止Web服务器
stop_web_ui() {
    log_info "停止Web UI服务器..."

    if [[ -n "${WEB_UI_PID}" ]] && kill -0 ${WEB_UI_PID} 2>/dev/null; then
        kill ${WEB_UI_PID}
        wait ${WEB_UI_PID} 2>/dev/null
    fi

    WEB_UI_RUNNING=false
    WEB_UI_PID=""

    log_info "Web UI服务器已停止"
    return 0
}

# 启动状态广播
start_status_broadcast() {
    while [[ "${WEB_UI_RUNNING}" == "true" ]]; do
        local status=$(get_system_status_json)
        broadcast_system_status "${status}"
        sleep 5
    done
}

# 服务器处理（通过socat调用）
handle_server() {
    local request=$(cat)

    # 检查是否是WebSocket升级请求
    if echo "${request}" | grep -qi "Upgrade: websocket"; then
        # WebSocket握手
        local client_fd=$(ls -la /proc/self/fd/ | grep -E "socket:\[" | awk '{print $9}')
        websocket_handshake "${request}" "${client_fd}"
    else
        # HTTP请求
        local client_fd=$(ls -la /proc/self/fd/ | grep -E "socket:\[" | awk '{print $9}')
        handle_http_request "${request}" "${client_fd}"
    fi
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f parse_http_request
export -f build_http_response
export -f register_route
export -f find_route
export -f handle_http_request
export -f check_authentication
export -f validate_user
export -f validate_session_token
export -f create_session_token
export -f websocket_handshake
export -f handle_websocket_messages
export -f read_websocket_frame
export -f send_websocket_frame
export -f handle_websocket_text
export -f send_websocket_pong
export -f close_websocket_connection
export -f subscribe_to_channel
export -f unsubscribe_from_channel
export -f broadcast_to_channel
export -f broadcast_system_status
export -f register_default_routes
export -f start_web_ui
export -f stop_web_ui
export -f handle_server
