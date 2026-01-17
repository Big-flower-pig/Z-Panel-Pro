#!/bin/bash
# ==============================================================================
# Z-Panel Pro - error_handler.sh 单元测试
# ==============================================================================

# 导入被测试模块
source "${SCRIPT_DIR}/../lib/error_handler.sh"
source "${SCRIPT_DIR}/../lib/core.sh"

# 测试日志目录
readonly TEST_LOG_DIR="/tmp/zpanel_test_logs"
mkdir -p "${TEST_LOG_DIR}"

# ==============================================================================
# 测试日志级别
# ==============================================================================

test_log_levels() {
    test_suite_start "日志级别"

    # 测试日志级别常量
    assert_equals "0" "${LOG_LEVEL_DEBUG}" "DEBUG level is 0"
    assert_equals "1" "${LOG_LEVEL_INFO}" "INFO level is 1"
    assert_equals "2" "${LOG_LEVEL_WARN}" "WARN level is 2"
    assert_equals "3" "${LOG_LEVEL_ERROR}" "ERROR level is 3"

    test_suite_end "日志级别"
}

# ==============================================================================
# 测试日志记录函数
# ==============================================================================

test_log_message() {
    test_suite_start "log_message"

    local test_log="${TEST_LOG_DIR}/test_log.log"
    init_logging "${test_log}"

    # 测试INFO级别日志
    log_message "INFO" "Test info message"
    assert_file_exists "${test_log}" "Log file exists"

    # 检查日志内容
    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Test info message" "Log contains test message"
    assert_contains "${log_content}" "[INFO]" "Log contains INFO tag"

    # 清理
    rm -f "${test_log}"

    test_suite_end "log_message"
}

test_log_debug() {
    test_suite_start "log_debug"

    local test_log="${TEST_LOG_DIR}/test_debug.log"
    init_logging "${test_log}"
    set_log_level "DEBUG"

    # 测试DEBUG日志
    log_debug "Debug message"
    assert_file_exists "${test_log}" "Debug log file exists"

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Debug message" "Log contains debug message"
    assert_contains "${log_content}" "[DEBUG]" "Log contains DEBUG tag"

    # 清理
    rm -f "${test_log}"

    test_suite_end "log_debug"
}

test_log_info() {
    test_suite_start "log_info"

    local test_log="${TEST_LOG_DIR}/test_info.log"
    init_logging "${test_log}"

    # 测试INFO日志
    log_info "Info message"

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Info message" "Log contains info message"
    assert_contains "${log_content}" "[INFO]" "Log contains INFO tag"

    # 清理
    rm -f "${test_log}"

    test_suite_end "log_info"
}

test_log_warn() {
    test_suite_start "log_warn"

    local test_log="${TEST_LOG_DIR}/test_warn.log"
    init_logging "${test_log}"

    # 测试WARN日志
    log_warn "Warning message"

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Warning message" "Log contains warning message"
    assert_contains "${log_content}" "[WARN]" "Log contains WARN tag"

    # 清理
    rm -f "${test_log}"

    test_suite_end "log_warn"
}

test_log_error() {
    test_suite_start "log_error"

    local test_log="${TEST_LOG_DIR}/test_error.log"
    init_logging "${test_log}"

    # 测试ERROR日志
    log_error "Error message"

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Error message" "Log contains error message"
    assert_contains "${log_content}" "[ERROR]" "Log contains ERROR tag"

    # 清理
    rm -f "${test_log}"

    test_suite_end "log_error"
}

# ==============================================================================
# 测试日志级别过滤
# ==============================================================================

test_log_level_filtering() {
    test_suite_start "日志级别过滤"

    local test_log="${TEST_LOG_DIR}/test_filter.log"
    init_logging "${test_log}"

    # 设置为ERROR级别
    set_log_level "ERROR"

    # 尝试记录不同级别的日志
    log_debug "Debug message"
    log_info "Info message"
    log_warn "Warning message"
    log_error "Error message"

    local log_content
    log_content=$(cat "${test_log}")

    # ERROR级别应该只记录ERROR日志
    assert_not_contains "${log_content}" "Debug message" "DEBUG not logged at ERROR level"
    assert_not_contains "${log_content}" "Info message" "INFO not logged at ERROR level"
    assert_not_contains "${log_content}" "Warning message" "WARN not logged at ERROR level"
    assert_contains "${log_content}" "Error message" "ERROR logged at ERROR level"

    # 清理
    rm -f "${test_log}"

    test_suite_end "日志级别过滤"
}

# ==============================================================================
# 测试错误处理
# ==============================================================================

test_handle_error_continue() {
    test_suite_start "handle_error (continue)"

    local test_log="${TEST_LOG_DIR}/test_error_continue.log"
    init_logging "${test_log}"

    # 测试continue动作（不退出）
    handle_error "Test error" "continue" "test_function"

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Test error" "Error message logged"
    assert_contains "${log_content}" "test_function" "Function name logged"

    # 清理
    rm -f "${test_log}"

    test_suite_end "handle_error (continue)"
}

test_handle_error_exit() {
    test_suite_start "handle_error (exit)"

    local test_log="${TEST_LOG_DIR}/test_error_exit.log"
    init_logging "${test_log}"

    # 测试exit动作（会退出脚本，这里只能测试日志记录）
    # 实际测试需要子进程
    (
        handle_error "Test error" "exit" "test_function"
    ) 2>/dev/null || true

    local log_content
    log_content=$(cat "${test_log}")
    assert_contains "${log_content}" "Test error" "Error message logged"

    # 清理
    rm -f "${test_log}"

    test_suite_end "handle_error (exit)"
}

# ==============================================================================
# 测试断言函数
# ==============================================================================

test_assert_equals() {
    test_suite_start "assert_equals"

    # 测试相等情况
    assert_equals "1" "1" "assert_equals should pass for equal values"

    # 测试不相等情况（会在子进程中测试）
    local result
    result=$(assert_equals "1" "2" "test" 2>&1 || echo "FAILED")
    assert_contains "${result}" "FAILED" "assert_equals should fail for unequal values"

    test_suite_end "assert_equals"
}

test_assert_not_empty() {
    test_suite_start "assert_not_empty"

    # 测试非空情况
    assert_not_empty "test" "assert_not_empty should pass for non-empty string"

    # 测试空情况
    local result
    result=$(assert_not_empty "" "test" 2>&1 || echo "FAILED")
    assert_contains "${result}" "FAILED" "assert_not_empty should fail for empty string"

    test_suite_end "assert_not_empty"
}

test_assert_file_exists() {
    test_suite_start "assert_file_exists"

    # 创建测试文件
    local test_file="${TEST_LOG_DIR}/test_file.txt"
    touch "${test_file}"

    # 测试文件存在
    assert_file_exists "${test_file}" "assert_file_exists should pass for existing file"

    # 测试文件不存在
    local result
    result=$(assert_file_exists "${TEST_LOG_DIR}/nonexistent.txt" "test" 2>&1 || echo "FAILED")
    assert_contains "${result}" "FAILED" "assert_file_exists should fail for non-existent file"

    # 清理
    rm -f "${test_file}"

    test_suite_end "assert_file_exists"
}

test_assert_command_exists() {
    test_suite_start "assert_command_exists"

    # 测试存在的命令
    assert_command_exists "bash" "assert_command_exists should pass for bash"
    assert_command_exists "ls" "assert_command_exists should pass for ls"

    # 测试不存在的命令
    local result
    result=$(assert_command_exists "nonexistent_command_xyz" "test" 2>&1 || echo "FAILED")
    assert_contains "${result}" "FAILED" "assert_command_exists should fail for non-existent command"

    test_suite_end "assert_command_exists"
}

# ==============================================================================
# 测试重试机制
# ==============================================================================

test_execute_with_retry() {
    test_suite_start "execute_with_retry"

    # 测试成功的命令（第一次就成功）
    local result
    result=$(execute_with_retry "echo 'success'" 3 1)
    assert_equals "success" "${result}" "Successful command should return output"

    # 测试失败的命令（重试后仍然失败）
    local test_log="${TEST_LOG_DIR}/test_retry.log"
    init_logging "${test_log}"

    result=$(execute_with_retry "false" 2 1 2>&1 || echo "FAILED")
    assert_contains "${result}" "FAILED" "Failed command should return FAILED"

    # 清理
    rm -f "${test_log}"

    test_suite_end "execute_with_retry"
}

# ==============================================================================
# 运行所有测试
# ==============================================================================

run_all_error_handler_tests() {
    # 日志级别测试
    test_log_levels

    # 日志记录测试
    test_log_message
    test_log_debug
    test_log_info
    test_log_warn
    test_log_error

    # 日志级别过滤测试
    test_log_level_filtering

    # 错误处理测试
    test_handle_error_continue
    test_handle_error_exit

    # 断言函数测试
    test_assert_equals
    test_assert_not_empty
    test_assert_file_exists
    test_assert_command_exists

    # 重试机制测试
    test_execute_with_retry
}

# 运行测试
run_all_error_handler_tests