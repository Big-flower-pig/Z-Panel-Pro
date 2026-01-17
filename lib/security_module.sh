#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 安全模块增强
# ==============================================================================
# @description    企业级安全模块，支持RBAC、审计日志、加密、威胁检测
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 安全模块配置
# ==============================================================================
declare -gA SECURITY_CONFIG=(
    [auth_method]="jwt"
    [session_timeout]="3600"
    [max_login_attempts]="5"
    [lockout_duration]="900"
    [password_min_length]="12"
    [password_require_uppercase]="true"
    [password_require_lowercase]="true"
    [password_require_number]="true"
    [password_require_special]="true"
    [encryption_algorithm]="AES-256-GCM"
    [audit_log_enabled]="true"
    [audit_log_file]="/opt/Z-Panel-Pro/logs/security/audit.log"
    [threat_detection_enabled]="true"
    [threat_threshold]="medium"
    [mfa_enabled]="false"
    [mfa_method]="totp"
    [password_hash_algorithm]="argon2id"
    [argon2_time_cost]="3"
    [argon2_memory_cost]="65536"
    [argon2_parallelism]="4"
    [argon2_salt_length]="32"
    [argon2_hash_length]="32"
)

# ==============================================================================
# 用户和角色
# ==============================================================================
declare -gA SECURITY_USERS=()
declare -gA SECURITY_ROLES=()
declare -gA SECURITY_PERMISSIONS=()
declare -gA SECURITY_SESSIONS=()

# ==============================================================================
# 审计日志
# ==============================================================================
declare -gA SECURITY_AUDIT_LOG=()

# ==============================================================================
# 威胁检测
# ==============================================================================
declare -gA SECURITY_THREATS=()
declare -gA SECURITY_THREAT_RULES=()

# ==============================================================================
# 加密密钥
# ==============================================================================
declare -g SECURITY_ENCRYPTION_KEY=""
declare -g SECURITY_ENCRYPTION_SALT=""

# ==============================================================================
# 初始化安全模块
# ==============================================================================
init_security_module() {
    log_info "初始化安全模块..."

    # 创建目录
    mkdir -p "$(dirname "${SECURITY_CONFIG[audit_log_file]}")"
    mkdir -p "/opt/Z-Panel-Pro/data/security"

    # 加载密钥
    load_encryption_keys

    # 加载用户和角色
    load_users_and_roles

    # 加载威胁规则
    load_threat_rules

    # 创建默认管理员
    create_default_admin

    log_info "安全模块初始化完成"
    return 0
}

# ==============================================================================
# 加密密钥管理
# ==============================================================================
# 加载加密密钥
load_encryption_keys() {
    local key_file="/opt/Z-Panel-Pro/data/security/encryption.key"

    if [[ ! -f "${key_file}" ]]; then
        # 生成新密钥
        generate_encryption_keys
        return 0
    fi

    # 读取密钥
    SECURITY_ENCRYPTION_KEY=$(head -n 1 "${key_file}")
    SECURITY_ENCRYPTION_SALT=$(tail -n 1 "${key_file}")

    log_debug "加密密钥已加载"
}

# 生成加密密钥
generate_encryption_keys() {
    local key_file="/opt/Z-Panel-Pro/data/security/encryption.key"

    # 生成随机密钥
    SECURITY_ENCRYPTION_KEY=$(openssl rand -hex 32)
    SECURITY_ENCRYPTION_SALT=$(openssl rand -hex 16)

    # 保存密钥
    echo "${SECURITY_ENCRYPTION_KEY}" > "${key_file}"
    echo "${SECURITY_ENCRYPTION_SALT}" >> "${key_file}"

    # 设置权限
    chmod 600 "${key_file}"

    log_info "加密密钥已生成"
}

# 加密数据
encrypt_data() {
    local data="$1"
    local key="${2:-${SECURITY_ENCRYPTION_KEY}}"

    if [[ -z "${data}" ]] || [[ -z "${key}" ]]; then
        log_error "缺少必需参数: data, key"
        return 1
    fi

    local iv=$(openssl rand -hex 16)
    local encrypted=$(echo -n "${data}" | openssl enc -aes-256-gcm -K "${key}" -iv "${iv}" -base64)
    local tag=$(echo "${encrypted}" | tail -c 16)

    echo "${iv}:${encrypted}"
}

# 解密数据
decrypt_data() {
    local encrypted_data="$1"
    local key="${2:-${SECURITY_ENCRYPTION_KEY}}"

    if [[ -z "${encrypted_data}" ]] || [[ -z "${key}" ]]; then
        log_error "缺少必需参数: encrypted_data, key"
        return 1
    fi

    local iv=$(echo "${encrypted_data}" | cut -d':' -f1)
    local encrypted=$(echo "${encrypted_data}" | cut -d':' -f2-)

    echo "${encrypted}" | openssl enc -aes-256-gcm -d -K "${key}" -iv "${iv}" -base64 2>/dev/null
}

# 生成Argon2id盐值
generate_argon2_salt() {
    openssl rand -hex "${SECURITY_CONFIG[argon2_salt_length]}"
}

# 哈希密码（使用Argon2id - 最安全的密码哈希算法）
hash_password() {
    local password="$1"
    local salt="${2:-$(generate_argon2_salt)}"

    if [[ -z "${password}" ]]; then
        log_error "缺少必需参数: password"
        return 1
    fi

    local time_cost="${SECURITY_CONFIG[argon2_time_cost]}"
    local memory_cost="${SECURITY_CONFIG[argon2_memory_cost]}"
    local parallelism="${SECURITY_CONFIG[argon2_parallelism]}"
    local hash_length="${SECURITY_CONFIG[argon2_hash_length]}"

    # 检查argon2命令是否可用
    if command -v argon2 &> /dev/null; then
        # 使用Argon2id（推荐用于密码哈希）
        local hash=$(echo -n "${password}" | argon2 "${salt}" \
            -id \
            -t "${time_cost}" \
            -m "${memory_cost}" \
            -p "${parallelism}" \
            -l "${hash_length}" \
            -e 2>/dev/null)

        if [[ $? -eq 0 ]] && [[ -n "${hash}" ]]; then
            echo "${salt}:${hash}"
            return 0
        fi
    fi

    # 降级方案：使用PBKDF2-SHA512（比原来的SHA256更安全）
    log_warning "argon2不可用，使用PBKDF2-SHA512降级方案"

    # 生成随机盐值
    local fallback_salt=$(generate_argon2_salt)

    # 使用更高的迭代次数（600,000次）和SHA512
    local hash=$(echo -n "${password}" | openssl dgst -pbkdf2 -iter 600000 -salt "${fallback_salt}" -sha512 -binary | base64 -w 0)

    # 存储算法标识符
    echo "PBKDF2-SHA512:600000:${fallback_salt}:${hash}"
}

# 验证密码（支持Argon2id和PBKDF2-SHA512）
verify_password() {
    local password="$1"
    local stored_hash="$2"

    if [[ -z "${password}" ]] || [[ -z "${stored_hash}" ]]; then
        log_error "缺少必需参数: password, stored_hash"
        return 1
    fi

    # 检查哈希格式
    if [[ "${stored_hash}" == "PBKDF2-SHA512:"* ]]; then
        # 解析PBKDF2-SHA512格式
        local parts=(${stored_hash//:/ })
        local algorithm="${parts[0]}"
        local iterations="${parts[1]}"
        local salt="${parts[2]}"
        local hash="${parts[3]}"

        # 计算哈希
        local computed_hash=$(echo -n "${password}" | openssl dgst -pbkdf2 -iter "${iterations}" -salt "${salt}" -sha512 -binary | base64 -w 0)

        # 使用恒定时间比较（防止时序攻击）
        if [[ ${#computed_hash} -eq ${#hash} ]]; then
            local match=true
            for ((i=0; i<${#computed_hash}; i++)); do
                if [[ "${computed_hash:$i:1}" != "${hash:$i:1}" ]]; then
                    match=false
                fi
            done
            if [[ "${match}" == "true" ]]; then
                return 0
            fi
        fi
        return 1
    elif [[ "${stored_hash}" == *":"* ]]; then
        # 解析Argon2id格式：salt:hash
        local salt="${stored_hash%%:*}"
        local hash="${stored_hash#*:}"

        # 检查argon2命令是否可用
        if command -v argon2 &> /dev/null; then
            local time_cost="${SECURITY_CONFIG[argon2_time_cost]}"
            local memory_cost="${SECURITY_CONFIG[argon2_memory_cost]}"
            local parallelism="${SECURITY_CONFIG[argon2_parallelism]}"
            local hash_length="${SECURITY_CONFIG[argon2_hash_length]}"

            # 计算哈希
            local computed_hash=$(echo -n "${password}" | argon2 "${salt}" \
                -id \
                -t "${time_cost}" \
                -m "${memory_cost}" \
                -p "${parallelism}" \
                -l "${hash_length}" \
                -e 2>/dev/null)

            if [[ $? -eq 0 ]] && [[ -n "${computed_hash}" ]]; then
                # 使用恒定时间比较
                if [[ ${#computed_hash} -eq ${#hash} ]]; then
                    local match=true
                    for ((i=0; i<${#computed_hash}; i++)); do
                        if [[ "${computed_hash:$i:1}" != "${hash:$i:1}" ]]; then
                            match=false
                        fi
                    done
                    if [[ "${match}" == "true" ]]; then
                        return 0
                    fi
                fi
            fi
            return 1
        else
            log_error "argon2命令不可用，无法验证Argon2id哈希"
            return 1
        fi
    else
        # 旧格式哈希（向后兼容）
        log_warning "使用旧的哈希格式，建议重新哈希密码"
        local computed_hash=$(echo -n "${password}" | openssl dgst -pbkdf2 -iter 100000 -salt "${SECURITY_ENCRYPTION_SALT}" -sha256 | cut -d' ' -f2)

        if [[ "${computed_hash}" == "${stored_hash}" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# ==============================================================================
# 用户管理
# ==============================================================================
# 创建用户
create_user() {
    local username="$1"
    local password="$2"
    local email="${3:-}"
    local role="${4:-user}"

    if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
        log_error "缺少必需参数: username, password"
        return 1
    fi

    # 检查用户是否已存在
    if [[ -n "${SECURITY_USERS[${username}_id]+isset}" ]]; then
        log_error "用户已存在: ${username}"
        return 1
    fi

    # 验证密码强度
    if ! validate_password_strength "${password}"; then
        log_error "密码强度不足"
        return 1
    fi

    # 哈希密码
    local password_hash=$(hash_password "${password}")

    # 创建用户
    local user_id="user_$(date +%s)_${RANDOM}"
    SECURITY_USERS["${username}_id"]="${user_id}"
    SECURITY_USERS["${username}_password_hash"]="${password_hash}"
    SECURITY_USERS["${username}_email"]="${email}"
    SECURITY_USERS["${username}_role"]="${role}"
    SECURITY_USERS["${username}_created"]=$(date +%s)
    SECURITY_USERS["${username}_status"]="active"
    SECURITY_USERS["${username}_login_attempts"]="0"
    SECURITY_USERS["${username}_last_login"]="0"
    SECURITY_USERS["${username}_locked_until"]="0"

    # 记录审计日志
    log_audit "user_created" "用户创建" "username=${username},role=${role}"

    log_info "用户已创建: ${username}"
    return 0
}

# 删除用户
delete_user() {
    local username="$1"

    if [[ -z "${username}" ]]; then
        log_error "缺少必需参数: username"
        return 1
    fi

    # 检查用户是否存在
    if [[ -z "${SECURITY_USERS[${username}_id]+isset}" ]]; then
        log_error "用户不存在: ${username}"
        return 1
    fi

    # 删除用户
    for key in "${!SECURITY_USERS[@]}"; do
        if [[ "${key}" == "${username}_"* ]]; then
            unset SECURITY_USERS["${key}"]
        fi
    done

    # 记录审计日志
    log_audit "user_deleted" "用户删除" "username=${username}"

    log_info "用户已删除: ${username}"
    return 0
}

# 验证密码强度
validate_password_strength() {
    local password="$1"

    if [[ ${#password} -lt ${SECURITY_CONFIG[password_min_length]} ]]; then
        log_error "密码长度不足（最少${SECURITY_CONFIG[password_min_length]}个字符）"
        return 1
    fi

    if [[ "${SECURITY_CONFIG[password_require_uppercase]}" == "true" ]]; then
        if [[ ! "${password}" =~ [A-Z] ]]; then
            log_error "密码必须包含大写字母"
            return 1
        fi
    fi

    if [[ "${SECURITY_CONFIG[password_require_lowercase]}" == "true" ]]; then
        if [[ ! "${password}" =~ [a-z] ]]; then
            log_error "密码必须包含小写字母"
            return 1
        fi
    fi

    if [[ "${SECURITY_CONFIG[password_require_number]}" == "true" ]]; then
        if [[ ! "${password}" =~ [0-9] ]]; then
            log_error "密码必须包含数字"
            return 1
        fi
    fi

    if [[ "${SECURITY_CONFIG[password_require_special]}" == "true" ]]; then
        if [[ ! "${password}" =~ [!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?] ]]; then
            log_error "密码必须包含特殊字符"
            return 1
        fi
    fi

    return 0
}

# ==============================================================================
# 认证和授权
# ==============================================================================
# 用户登录
authenticate_user() {
    local username="$1"
    local password="$2"
    local client_ip="${3:-}"

    if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
        log_error "缺少必需参数: username, password"
        return 1
    fi

    # 检查用户是否存在
    if [[ -z "${SECURITY_USERS[${username}_id]+isset}" ]]; then
        log_audit "auth_failed" "认证失败" "username=${username},reason=user_not_found,ip=${client_ip}"
        return 1
    fi

    # 检查用户状态
    local user_status="${SECURITY_USERS[${username}_status]}"
    if [[ "${user_status}" != "active" ]]; then
        log_audit "auth_failed" "认证失败" "username=${username},reason=user_${user_status},ip=${client_ip}"
        return 1
    fi

    # 检查账户锁定状态
    local locked_until="${SECURITY_USERS[${username}_locked_until]}"
    local current_time=$(date +%s)
    if [[ ${locked_until} -gt ${current_time} ]]; then
        local lock_duration=$((locked_until - current_time))
        log_audit "auth_failed" "认证失败" "username=${username},reason=account_locked,lock_duration=${lock_duration},ip=${client_ip}"
        return 1
    fi

    # 验证密码
    local stored_hash="${SECURITY_USERS[${username}_password_hash]}"
    if ! verify_password "${password}" "${stored_hash}"; then
        # 增加登录失败次数
        local attempts=$((SECURITY_USERS[${username}_login_attempts}] + 1))
        SECURITY_USERS["${username}_login_attempts"]="${attempts}"

        # 检查是否需要锁定账户
        if [[ ${attempts} -ge ${SECURITY_CONFIG[max_login_attempts]} ]]; then
            local lockout_time=$((current_time + SECURITY_CONFIG[lockout_duration]))
            SECURITY_USERS["${username}_locked_until"]="${lockout_time}"
            SECURITY_USERS["${username}_login_attempts"]="0"

            log_audit "account_locked" "账户锁定" "username=${username},attempts=${attempts},ip=${client_ip}"
        fi

        log_audit "auth_failed" "认证失败" "username=${username},reason=invalid_password,attempts=${attempts},ip=${client_ip}"
        return 1
    fi

    # 重置登录失败次数
    SECURITY_USERS["${username}_login_attempts"]="0"

    # 创建会话
    local session_id=$(create_session "${username}" "${client_ip}")

    # 更新最后登录时间
    SECURITY_USERS["${username}_last_login"]="${current_time}"

    # 记录审计日志
    log_audit "auth_success" "认证成功" "username=${username},session_id=${session_id},ip=${client_ip}"

    echo "${session_id}"
    return 0
}

# 创建会话
create_session() {
    local username="$1"
    local client_ip="${2:-}"

    local session_id="session_$(date +%s)_${RANDOM}"
    local expires_at=$(($(date +%s) + SECURITY_CONFIG[session_timeout]))

    SECURITY_SESSIONS["${session_id}_username"]="${username}"
    SECURITY_SESSIONS["${session_id}_created"]=$(date +%s)
    SECURITY_SESSIONS["${session_id}_expires_at"]="${expires_at}"
    SECURITY_SESSIONS["${session_id}_client_ip"]="${client_ip}"
    SECURITY_SESSIONS["${session_id}_user_agent"]="${HTTP_USER_AGENT:-}"

    # 生成JWT令牌
    local jwt_token=$(generate_jwt_token "${session_id}" "${username}")
    SECURITY_SESSIONS["${session_id}_jwt_token"]="${jwt_token}"

    log_debug "会话已创建: ${session_id}"
    echo "${session_id}"
}

# 验证会话
validate_session() {
    local session_id="$1"

    if [[ -z "${session_id}" ]]; then
        return 1
    fi

    # 检查会话是否存在
    if [[ -z "${SECURITY_SESSIONS[${session_id}_username]+isset}" ]]; then
        return 1
    fi

    # 检查会话是否过期
    local expires_at="${SECURITY_SESSIONS[${session_id}_expires_at]}"
    local current_time=$(date +%s)

    if [[ ${expires_at} -lt ${current_time} ]]; then
        # 删除过期会话
        delete_session "${session_id}"
        return 1
    fi

    # 更新会话过期时间
    SECURITY_SESSIONS["${session_id}_expires_at"]=$((current_time + SECURITY_CONFIG[session_timeout]))

    return 0
}

# 删除会话
delete_session() {
    local session_id="$1"

    for key in "${!SECURITY_SESSIONS[@]}"; do
        if [[ "${key}" == "${session_id}_"* ]]; then
            unset SECURITY_SESSIONS["${key}"]
        fi
    done

    log_debug "会话已删除: ${session_id}"
}

# 生成JWT令牌（安全增强版本）
generate_jwt_token() {
    local session_id="$1"
    local username="$2"
    local token_type="${3:-access}"  # access 或 refresh

    local iat=$(date +%s)
    local exp=$((iat + SECURITY_CONFIG[session_timeout]))
    local nbf=${iat}
    local jti="jti_$(date +%s%N)_${RANDOM}"
    local iss="Z-Panel-Pro"

    # 刷新令牌的有效期更长（7天）
    if [[ "${token_type}" == "refresh" ]]; then
        exp=$((iat + 604800))  # 7天
    fi

    local header='{"alg":"HS256","typ":"JWT","kid":"1"}'
    local payload=$(cat <<EOF
{
    "iss": "${iss}",
    "sub": "${username}",
    "aud": "Z-Panel-Pro-API",
    "session_id": "${session_id}",
    "username": "${username}",
    "iat": ${iat},
    "nbf": ${nbf},
    "exp": ${exp},
    "jti": "${jti}",
    "type": "${token_type}"
}
EOF
)

    local header_base64=$(echo -n "${header}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    local payload_base64=$(echo -n "${payload}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')

    local signature=$(echo -n "${header_base64}.${payload_base64}" | openssl dgst -sha256 -hmac "${SECURITY_ENCRYPTION_KEY}" -binary | base64 -w 0 | tr '+/' '-_' | tr -d '=')

    echo "${header_base64}.${payload_base64}.${signature}"
}

# 验证JWT令牌（安全增强版本）
verify_jwt_token() {
    local token="$1"
    local token_type="${2:-access}"

    # 基本格式验证
    if [[ -z "${token}" ]]; then
        log_warning "JWT令牌为空"
        return 1
    fi

    local parts=(${token//./ })
    if [[ ${#parts[@]} -ne 3 ]]; then
        log_warning "JWT令牌格式无效"
        return 1
    fi

    local header_base64="${parts[0]}"
    local payload_base64="${parts[1]}"
    local signature="${parts[2]}"

    # 解码并验证header
    local header=$(echo -n "${header_base64}" | base64 -d 2>/dev/null)
    if [[ -z "${header}" ]]; then
        log_warning "JWT header解码失败"
        return 1
    fi

    # 验证算法（防止算法降级攻击）
    local alg=$(echo "${header}" | grep -o '"alg":"[^"]*"' | cut -d'"' -f4)
    if [[ "${alg}" != "HS256" ]]; then
        log_warning "JWT算法不被允许: ${alg}"
        return 1
    fi

    # 验证签名
    local computed_signature=$(echo -n "${header_base64}.${payload_base64}" | openssl dgst -sha256 -hmac "${SECURITY_ENCRYPTION_KEY}" -binary | base64 -w 0 | tr '+/' '-_' | tr -d '=')

    # 使用恒定时间比较（防止时序攻击）
    if [[ ${#signature} -ne ${#computed_signature} ]]; then
        log_warning "JWT签名验证失败（长度不匹配）"
        return 1
    fi

    local match=true
    for ((i=0; i<${#signature}; i++)); do
        if [[ "${signature:$i:1}" != "${computed_signature:$i:1}" ]]; then
            match=false
        fi
    done

    if [[ "${match}" == "false" ]]; then
        log_warning "JWT签名验证失败"
        return 1
    fi

    # 解码payload
    local payload=$(echo -n "${payload_base64}" | base64 -d 2>/dev/null)
    if [[ -z "${payload}" ]]; then
        log_warning "JWT payload解码失败"
        return 1
    fi

    # 验证标准声明
    local iss=$(echo "${payload}" | grep -o '"iss":"[^"]*"' | cut -d'"' -f4)
    local sub=$(echo "${payload}" | grep -o '"sub":"[^"]*"' | cut -d'"' -f4)
    local aud=$(echo "${payload}" | grep -o '"aud":"[^"]*"' | cut -d'"' -f4)
    local iat=$(echo "${payload}" | grep -o '"iat":[0-9]*' | cut -d':' -f2)
    local nbf=$(echo "${payload}" | grep -o '"nbf":[0-9]*' | cut -d':' -f2)
    local exp=$(echo "${payload}" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
    local jti=$(echo "${payload}" | grep -o '"jti":"[^"]*"' | cut -d'"' -f4)
    local type=$(echo "${payload}" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)

    # 验证iss（发行者）
    if [[ "${iss}" != "Z-Panel-Pro" ]]; then
        log_warning "JWT发行者无效: ${iss}"
        return 1
    fi

    # 验证aud（受众）
    if [[ "${aud}" != "Z-Panel-Pro-API" ]]; then
        log_warning "JWT受众无效: ${aud}"
        return 1
    fi

    # 验证sub（主题）
    if [[ -z "${sub}" ]]; then
        log_warning "JWT主题为空"
        return 1
    fi

    # 验证iat（签发时间）
    if [[ -z "${iat}" ]] || [[ ${iat} -lt 0 ]]; then
        log_warning "JWT签发时间无效: ${iat}"
        return 1
    fi

    # 验证nbf（不早于）
    if [[ -n "${nbf}" ]]; then
        local current_time=$(date +%s)
        if [[ ${current_time} -lt ${nbf} ]]; then
            log_warning "JWT尚未生效（nbf: ${nbf}, current: ${current_time}）"
            return 1
        fi
    fi

    # 验证exp（过期时间）
    if [[ -z "${exp}" ]] || [[ ${exp} -le 0 ]]; then
        log_warning "JWT过期时间无效: ${exp}"
        return 1
    fi

    local current_time=$(date +%s)
    if [[ ${exp} -lt ${current_time} ]]; then
        log_warning "JWT已过期（exp: ${exp}, current: ${current_time}）"
        return 1
    fi

    # 验证jti（JWT ID）
    if [[ -z "${jti}" ]]; then
        log_warning "JWT ID为空"
        return 1
    fi

    # 验证token类型
    if [[ "${type}" != "${token_type}" ]]; then
        log_warning "JWT令牌类型不匹配（期望: ${token_type}, 实际: ${type}）"
        return 1
    fi

    return 0
}

# 刷新访问令牌
refresh_access_token() {
    local refresh_token="$1"

    # 验证刷新令牌
    if ! verify_jwt_token "${refresh_token}" "refresh"; then
        log_warning "刷新令牌验证失败"
        return 1
    fi

    # 解码payload获取用户信息
    local parts=(${refresh_token//./ })
    local payload_base64="${parts[1]}"
    local payload=$(echo -n "${payload_base64}" | base64 -d 2>/dev/null)

    local session_id=$(echo "${payload}" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    local username=$(echo "${payload}" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    local jti=$(echo "${payload}" | grep -o '"jti":"[^"]*"' | cut -d'"' -f4)

    # 验证会话是否仍然有效
    if ! validate_session "${session_id}"; then
        log_warning "会话已过期或无效: ${session_id}"
        return 1
    fi

    # 检查刷新令牌是否已被撤销（可选实现）
    # ...

    # 生成新的访问令牌
    local new_access_token=$(generate_jwt_token "${session_id}" "${username}" "access")

    # 生成新的刷新令牌（轮换刷新令牌）
    local new_refresh_token=$(generate_jwt_token "${session_id}" "${username}" "refresh")

    log_audit "token_refreshed" "令牌刷新" "username=${username},old_jti=${jti},new_jti=$(echo "${new_refresh_token}" | cut -d'.' -f3 | cut -c1-16)}"

    # 返回JSON格式的响应
    cat <<EOF
{
    "access_token": "${new_access_token}",
    "refresh_token": "${new_refresh_token}",
    "token_type": "Bearer",
    "expires_in": ${SECURITY_CONFIG[session_timeout]}
}
EOF

    return 0
}

# ==============================================================================
# RBAC (基于角色的访问控制)
# ==============================================================================
# 创建角色
create_role() {
    local role_name="$1"
    local description="${2:-}"

    if [[ -z "${role_name}" ]]; then
        log_error "缺少必需参数: role_name"
        return 1
    fi

    if [[ -n "${SECURITY_ROLES[${role_name}_id]+isset}" ]]; then
        log_error "角色已存在: ${role_name}"
        return 1
    fi

    SECURITY_ROLES["${role_name}_id"]="role_$(date +%s)_${RANDOM}"
    SECURITY_ROLES["${role_name}_description"]="${description}"
    SECURITY_ROLES["${role_name}_created"]=$(date +%s)"

    log_info "角色已创建: ${role_name}"
}

# 添加权限到角色
add_permission_to_role() {
    local role_name="$1"
    local permission="$2"

    if [[ -z "${role_name}" ]] || [[ -z "${permission}" ]]; then
        log_error "缺少必需参数: role_name, permission"
        return 1
    fi

    local permissions="${SECURITY_ROLES[${role_name}_permissions]:-}"

    if [[ -n "${permissions}" ]]; then
        if [[ "${permissions}" != *"${permission}"* ]]; then
            SECURITY_ROLES["${role_name}_permissions"]="${permissions},${permission}"
        fi
    else
        SECURITY_ROLES["${role_name}_permissions"]="${permission}"
    fi

    log_debug "权限已添加到角色: ${role_name} -> ${permission}"
}

# 检查权限
check_permission() {
    local username="$1"
    local permission="$2"

    if [[ -z "${username}" ]] || [[ -z "${permission}" ]]; then
        return 1
    fi

    # 获取用户角色
    local user_role="${SECURITY_USERS[${username}_role]:-}"

    if [[ -z "${user_role}" ]]; then
        return 1
    fi

    # 获取角色权限
    local role_permissions="${SECURITY_ROLES[${user_role}_permissions]:-}"

    if [[ "${role_permissions}" == *"${permission}"* ]]; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 审计日志
# ==============================================================================
# 记录审计日志
log_audit() {
    local event_type="$1"
    local event_name="$2"
    local event_data="${3:-}"

    if [[ "${SECURITY_CONFIG[audit_log_enabled]}" != "true" ]]; then
        return 0
    fi

    local timestamp=$(date -Iseconds)
    local audit_entry="${timestamp} [${event_type}] ${event_name} ${event_data}"

    # 写入日志文件
    echo "${audit_entry}" >> "${SECURITY_CONFIG[audit_log_file]}"

    # 存储到内存
    local log_id="audit_$(date +%s)_${RANDOM}"
    SECURITY_AUDIT_LOG["${log_id}_timestamp"]="${timestamp}"
    SECURITY_AUDIT_LOG["${log_id}_type"]="${event_type}"
    SECURITY_AUDIT_LOG["${log_id}_name"]="${event_name}"
    SECURITY_AUDIT_LOG["${log_id}_data"]="${event_data}"

    log_debug "审计日志已记录: ${event_type}"
}

# 查询审计日志
query_audit_log() {
    local event_type="${1:-}"
    local start_time="${2:-}"
    local end_time="${3:-}"

    local results=""

    for key in "${!SECURITY_AUDIT_LOG[@]}"; do
        if [[ "${key}" == *"_type" ]]; then
            local log_id="${key%_type}"
            local log_type="${SECURITY_AUDIT_LOG[${key}]}"

            # 过滤事件类型
            if [[ -n "${event_type}" ]] && [[ "${log_type}" != "${event_type}" ]]; then
                continue
            fi

            # 过滤时间范围
            local log_timestamp="${SECURITY_AUDIT_LOG[${log_id}_timestamp]}"
            if [[ -n "${start_time}" ]] && [[ "${log_timestamp}" < "${start_time}" ]]; then
                continue
            fi
            if [[ -n "${end_time}" ]] && [[ "${log_timestamp}" > "${end_time}" ]]; then
                continue
            fi

            # 添加到结果
            results+="${log_timestamp} [${log_type}] ${SECURITY_AUDIT_LOG[${log_id}_name]} ${SECURITY_AUDIT_LOG[${log_id}_data]}"$'\n'
        fi
    done

    echo "${results}"
}

# ==============================================================================
# 威胁检测
# ==============================================================================
# 加载威胁规则
load_threat_rules() {
    # 暴力破解检测
    SECURITY_THREAT_RULES["brute_force_enabled"]="true"
    SECURITY_THREAT_RULES["brute_force_threshold"]="5"
    SECURITY_THREAT_RULES["brute_force_window"]="300"

    # 异常登录检测
    SECURITY_THREAT_RULES["abnormal_login_enabled"]="true"
    SECURITY_THREAT_RULES["abnormal_login_distance"]="1000"

    # SQL注入检测
    SECURITY_THREAT_RULES["sql_injection_enabled"]="true"

    # XSS攻击检测
    SECURITY_THREAT_RULES["xss_enabled"]="true"
}

# 检测威胁
detect_threat() {
    local threat_type="$1"
    local threat_data="$2"

    if [[ "${SECURITY_CONFIG[threat_detection_enabled]}" != "true" ]]; then
        return 0
    fi

    case "${threat_type}" in
        brute_force)
            detect_brute_force "${threat_data}"
            ;;
        abnormal_login)
            detect_abnormal_login "${threat_data}"
            ;;
        sql_injection)
            detect_sql_injection "${threat_data}"
            ;;
        xss)
            detect_xss "${threat_data}"
            ;;
    esac
}

# 检测暴力破解
detect_brute_force() {
    local username="$1"
    local client_ip="$2"

    local attempts_file="/opt/Z-Panel-Pro/tmp/threats/${client_ip}.attempts"
    mkdir -p "$(dirname "${attempts_file}")"

    local current_time=$(date +%s)
    local attempts="1"

    if [[ -f "${attempts_file}" ]]; then
        attempts=$(cat "${attempts_file}")
        attempts=$((attempts + 1))
    fi

    echo "${attempts}" > "${attempts_file}"

    local threshold="${SECURITY_THREAT_RULES[brute_force_threshold]}"

    if [[ ${attempts} -ge ${threshold} ]]; then
        local threat_id="threat_$(date +%s)_${RANDOM}"
        SECURITY_THREATS["${threat_id}_type"]="brute_force"
        SECURITY_THREATS["${threat_id}_username"]="${username}"
        SECURITY_THREATS["${threat_id}_ip"]="${client_ip}"
        SECURITY_THREATS["${threat_id}_timestamp"]="${current_time}"
        SECURITY_THREATS["${threat_id}_severity"]="high"
        SECURITY_THREATS["${threat_id}_status"]="active"

        log_audit "threat_detected" "威胁检测" "type=brute_force,username=${username},ip=${client_ip},attempts=${attempts}"

        # 触发告警
        trigger_threat_alert "${threat_id}"
    fi
}

# 检测异常登录
detect_abnormal_login() {
    local username="$1"
    local client_ip="$2"

    # 获取用户历史登录IP
    local last_login_ip="${SECURITY_USERS[${username}_last_login_ip]:-}"

    if [[ -n "${last_login_ip}" ]] && [[ "${last_login_ip}" != "${client_ip}" ]]; then
        # 简化实现：实际应该计算地理位置距离
        local threat_id="threat_$(date +%s)_${RANDOM}"
        SECURITY_THREATS["${threat_id}_type"]="abnormal_login"
        SECURITY_THREATS["${threat_id}_username"]="${username}"
        SECURITY_THREATS["${threat_id}_ip"]="${client_ip}"
        SECURITY_THREATS["${threat_id}_last_ip"]="${last_login_ip}"
        SECURITY_THREATS["${threat_id}_timestamp"]=$(date +%s)
        SECURITY_THREATS["${threat_id}_severity"]="medium"
        SECURITY_THREATS["${threat_id}_status"]="active"

        log_audit "threat_detected" "威胁检测" "type=abnormal_login,username=${username},ip=${client_ip},last_ip=${last_login_ip}"
    fi
}

# 检测SQL注入
detect_sql_injection() {
    local input="$1"

    local sql_patterns=(
        "' OR '1'='1"
        "' OR 1=1--"
        "' UNION SELECT"
        "DROP TABLE"
        "DELETE FROM"
        "INSERT INTO"
        "UPDATE.*SET"
        "EXEC("
        "xp_cmdshell"
    )

    for pattern in "${sql_patterns[@]}"; do
        if [[ "${input}" =~ ${pattern} ]]; then
            local threat_id="threat_$(date +%s)_${RANDOM}"
            SECURITY_THREATS["${threat_id}_type"]="sql_injection"
            SECURITY_THREATS["${threat_id}_input"]="${input}"
            SECURITY_THREATS["${threat_id}_pattern"]="${pattern}"
            SECURITY_THREATS["${threat_id}_timestamp"]=$(date +%s)
            SECURITY_THREATS["${threat_id}_severity"]="critical"
            SECURITY_THREATS["${threat_id}_status"]="active"

            log_audit "threat_detected" "威胁检测" "type=sql_injection,pattern=${pattern}"

            trigger_threat_alert "${threat_id}"
            return 1
        fi
    done

    return 0
}

# 检测XSS攻击
detect_xss() {
    local input="$1"

    local xss_patterns=(
        "<script>"
        "javascript:"
        "onerror="
        "onload="
        "onclick="
        "eval("
        "document.cookie"
    )

    for pattern in "${xss_patterns[@]}"; do
        if [[ "${input}" =~ ${pattern} ]]; then
            local threat_id="threat_$(date +%s)_${RANDOM}"
            SECURITY_THREATS["${threat_id}_type"]="xss"
            SECURITY_THREATS["${threat_id}_input"]="${input}"
            SECURITY_THREATS["${threat_id}_pattern"]="${pattern}"
            SECURITY_THREATS["${threat_id}_timestamp"]=$(date +%s)
            SECURITY_THREATS["${threat_id}_severity"]="high"
            SECURITY_THREATS["${threat_id}_status"]="active"

            log_audit "threat_detected" "威胁检测" "type=xss,pattern=${pattern}"

            trigger_threat_alert "${threat_id}"
            return 1
        fi
    done

    return 0
}

# 触发威胁告警
trigger_threat_alert() {
    local threat_id="$1"

    local threat_type="${SECURITY_THREATS[${threat_id}_type]}"
    local severity="${SECURITY_THREATS[${threat_id}_severity]}"

    # 发送告警事件
    local alert_data=$(cat <<EOF
{
    "threat_id": "${threat_id}",
    "threat_type": "${threat_type}",
    "severity": "${severity}",
    "timestamp": $(date +%s)
}
EOF
)

    publish_event "security" "${alert_data}" "threat_detection" "type=${threat_type},severity=${severity}"

    log_warning "威胁告警: ${threat_type} (${severity})"
}

# ==============================================================================
# 默认管理员
# ==============================================================================
# 创建默认管理员（安全版本）
create_default_admin() {
    if [[ -z "${SECURITY_USERS[admin_id]+isset}" ]]; then
        # 创建admin角色
        create_role "admin" "管理员角色"
        add_permission_to_role "admin" "*"

        # 生成强随机密码
        local admin_password=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
        local password_file="/opt/Z-Panel-Pro/data/security/.admin_password"

        # 创建默认管理员
        create_user "admin" "${admin_password}" "admin@zpanel.local" "admin"

        # 标记为首次登录（强制修改密码）
        SECURITY_USERS["admin_first_login"]="true"

        # 安全保存初始密码
        mkdir -p "$(dirname "${password_file}")"
        echo "用户名: admin" > "${password_file}"
        echo "初始密码: ${admin_password}" >> "${password_file}"
        chmod 600 "${password_file}"

        log_info "默认管理员已创建"
        log_warning "初始密码已保存到: ${password_file}"
        log_warning "首次登录时必须修改密码！"
    fi
}

# 安全加载用户和角色（防止代码注入）
load_users_and_roles() {
    local users_file="/opt/Z-Panel-Pro/data/security/users.db"
    local roles_file="/opt/Z-Panel-Pro/data/security/roles.db"

    # 验证文件路径安全性
    if [[ -f "${users_file}" ]]; then
        # 验证文件不是符号链接
        if [[ -L "${users_file}" ]]; then
            log_error "拒绝加载符号链接文件: ${users_file}"
            return 1
        fi

        # 验证文件权限
        local file_perms=$(stat -c "%a" "${users_file}" 2>/dev/null)
        if [[ "${file_perms}" != "600" ]] && [[ "${file_perms}" != "400" ]]; then
            log_error "文件权限不安全: ${users_file} (${file_perms})"
            return 1
        fi

        # 使用安全的解析方法而非source
        if command -v jq &> /dev/null; then
            # JSON格式解析
            local user_count=$(jq '.users | length' "${users_file}" 2>/dev/null)
            for ((i=0; i<user_count; i++)); do
                local username=$(jq -r ".users[${i}].username" "${users_file}")
                local password_hash=$(jq -r ".users[${i}].password_hash" "${users_file}")
                local email=$(jq -r ".users[${i}].email" "${users_file}")
                local role=$(jq -r ".users[${i}].role" "${users_file}")
                local created=$(jq -r ".users[${i}].created" "${users_file}")
                local status=$(jq -r ".users[${i}].status" "${users_file}")

                SECURITY_USERS["${username}_id"]="user_${created}_${RANDOM}"
                SECURITY_USERS["${username}_password_hash"]="${password_hash}"
                SECURITY_USERS["${username}_email"]="${email}"
                SECURITY_USERS["${username}_role"]="${role}"
                SECURITY_USERS["${username}_created"]="${created}"
                SECURITY_USERS["${username}_status"]="${status}"
                SECURITY_USERS["${username}_login_attempts"]="0"
                SECURITY_USERS["${username}_last_login"]="0"
                SECURITY_USERS["${username}_locked_until"]="0"
            done
        else
            # 降级为安全的bash解析（仅解析特定格式的变量）
            while IFS='=' read -r key value; do
                # 仅允许SECURITY_USERS前缀的变量
                if [[ "${key}" =~ ^SECURITY_USERS\[.+\]$ ]]; then
                    # 移除引号并验证值不包含危险字符
                    value="${value#\"}"
                    value="${value%\"}"

                    # 验证值不包含命令注入
                    if [[ "${value}" =~ \$|\`|\(|\;|\|\||&& ]]; then
                        log_error "检测到危险字符，跳过: ${key}"
                        continue
                    fi

                    # 安全赋值
                    eval "${key}=\"${value}\""
                fi
            done < "${users_file}"
        fi
    fi

    if [[ -f "${roles_file}" ]]; then
        # 验证文件不是符号链接
        if [[ -L "${roles_file}" ]]; then
            log_error "拒绝加载符号链接文件: ${roles_file}"
            return 1
        fi

        # 验证文件权限
        local file_perms=$(stat -c "%a" "${roles_file}" 2>/dev/null)
        if [[ "${file_perms}" != "600" ]] && [[ "${file_perms}" != "400" ]]; then
            log_error "文件权限不安全: ${roles_file} (${file_perms})"
            return 1
        fi

        # 使用安全的解析方法
        if command -v jq &> /dev/null; then
            # JSON格式解析
            local role_count=$(jq '.roles | length' "${roles_file}" 2>/dev/null)
            for ((i=0; i<role_count; i++)); do
                local role_name=$(jq -r ".roles[${i}].role_name" "${roles_file}")
                local description=$(jq -r ".roles[${i}].description" "${roles_file}")
                local created=$(jq -r ".roles[${i}].created" "${roles_file}")
                local permissions=$(jq -r ".roles[${i}].permissions | join(\",\")" "${roles_file}")

                SECURITY_ROLES["${role_name}_id"]="role_${created}_${RANDOM}"
                SECURITY_ROLES["${role_name}_description"]="${description}"
                SECURITY_ROLES["${role_name}_created"]="${created}"
                SECURITY_ROLES["${role_name}_permissions"]="${permissions}"
            done
        else
            # 降级为安全的bash解析
            while IFS='=' read -r key value; do
                # 仅允许SECURITY_ROLES前缀的变量
                if [[ "${key}" =~ ^SECURITY_ROLES\[.+\]$ ]]; then
                    # 移除引号并验证值不包含危险字符
                    value="${value#\"}"
                    value="${value%\"}"

                    # 验证值不包含命令注入
                    if [[ "${value}" =~ \$|\`|\(|\;|\|\||&& ]]; then
                        log_error "检测到危险字符，跳过: ${key}"
                        continue
                    fi

                    # 安全赋值
                    eval "${key}=\"${value}\""
                fi
            done < "${roles_file}"
        fi
    fi

    log_debug "用户和角色已安全加载"
}

# 保存用户和角色
save_users_and_roles() {
    local users_file="/opt/Z-Panel-Pro/data/security/users.db"
    local roles_file="/opt/Z-Panel-Pro/data/security/roles.db"

    # 保存用户
    declare -p SECURITY_USERS > "${users_file}"

    # 保存角色
    declare -p SECURITY_ROLES > "${roles_file}"

    log_debug "用户和角色已保存"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_security_module
export -f load_encryption_keys
export -f generate_encryption_keys
export -f encrypt_data
export -f decrypt_data
export -f generate_argon2_salt
export -f hash_password
export -f verify_password
export -f create_user
export -f delete_user
export -f validate_password_strength
export -f authenticate_user
export -f create_session
export -f validate_session
export -f delete_session
export -f generate_jwt_token
export -f verify_jwt_token
export -f refresh_access_token
export -f create_role
export -f add_permission_to_role
export -f check_permission
export -f log_audit
export -f query_audit_log
export -f load_threat_rules
export -f detect_threat
export -f detect_brute_force
export -f detect_abnormal_login
export -f detect_sql_injection
export -f detect_xss
export -f trigger_threat_alert
export -f create_default_admin
export -f load_users_and_roles
export -f save_users_and_roles
