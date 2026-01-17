#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 单元测试运行�?# ==============================================================================
# @description    单元测试框架和测试运行器
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 测试框架核心
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
readonly TEST_DIR="${SCRIPT_DIR}"

# 测试统计
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()

# 颜色定义
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# ==============================================================================
# 断言函数
# ==============================================================================

# 断言相等
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '${expected}' to equal '${actual}'}"

    ((TESTS_RUN++))

    if [[ "${expected}" == "${actual}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} '${expected}'"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} '${actual}'"
        return 1
    fi
}

# 断言不相�?assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '${expected}' to not equal '${actual}'}"

    ((TESTS_RUN++))

    if [[ "${expected}" != "${actual}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} not '${expected}'"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} '${actual}'"
        return 1
    fi
}

# 断言为真
assert_true() {
    local condition="$1"
    local message="${2:-Expected condition to be true}"

    ((TESTS_RUN++))

    if [[ "${condition}" == "true" ]] || [[ "${condition}" == "1" ]] || [[ "${condition}" -eq 1 ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} true"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} '${condition}'"
        return 1
    fi
}

# 断言为假
assert_false() {
    local condition="$1"
    local message="${2:-Expected condition to be false}"

    ((TESTS_RUN++))

    if [[ "${condition}" == "false" ]] || [[ "${condition}" == "0" ]] || [[ "${condition}" -eq 0 ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} false"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} '${condition}'"
        return 1
    fi
}

# 断言包含
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected '${haystack}' to contain '${needle}'}"

    ((TESTS_RUN++))

    if [[ "${haystack}" == *"${needle}"* ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} '${haystack}' to contain '${needle}'"
        return 1
    fi
}

# 断言为空
assert_empty() {
    local value="$1"
    local message="${2:-Expected value to be empty}"

    ((TESTS_RUN++))

    if [[ -z "${value}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} empty"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} '${value}'"
        return 1
    fi
}

# 断言不为�?assert_not_empty() {
    local value="$1"
    local message="${2:-Expected value to not be empty}"

    ((TESTS_RUN++))

    if [[ -n "${value}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} not empty"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} empty"
        return 1
    fi
}

# 断言大于
assert_greater_than() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Expected '${actual}' to be greater than '${expected}'}"

    ((TESTS_RUN++))

    if [[ ${actual} -gt ${expected} ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} > ${expected}"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} ${actual}"
        return 1
    fi
}

# 断言小于
assert_less_than() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Expected '${actual}' to be less than '${expected}'}"

    ((TESTS_RUN++))

    if [[ ${actual} -lt ${expected} ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Expected:${COLOR_NC} < ${expected}"
        echo -e "  ${COLOR_YELLOW}Actual:${COLOR_NC} ${actual}"
        return 1
    fi
}

# 断言文件存在
assert_file_exists() {
    local file="$1"
    local message="${2:-Expected file '${file}' to exist}"

    ((TESTS_RUN++))

    if [[ -f "${file}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}File:${COLOR_NC} '${file}' does not exist"
        return 1
    fi
}

# 断言文件不存�?assert_file_not_exists() {
    local file="$1"
    local message="${2:-Expected file '${file}' to not exist}"

    ((TESTS_RUN++))

    if [[ ! -f "${file}" ]]; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}File:${COLOR_NC} '${file}' exists"
        return 1
    fi
}

# 断言命令成功
assert_command_success() {
    local command="$1"
    local message="${2:-Expected command to succeed: ${command}}"

    ((TESTS_RUN++))

    if eval "${command}" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Command:${COLOR_NC} ${command}"
        return 1
    fi
}

# 断言命令失败
assert_command_failure() {
    local command="$1"
    local message="${2:-Expected command to fail: ${command}"

    ((TESTS_RUN++))

    if ! eval "${command}" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} ${message}"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${message}")
        echo -e "${COLOR_RED}[FAIL]${COLOR_NC} ${message}"
        echo -e "  ${COLOR_YELLOW}Command:${COLOR_NC} ${command}"
        return 1
    fi
}

# ==============================================================================
# 测试套件管理
# ==============================================================================

# 开始测试套�?test_suite_start() {
    local name="$1"
    echo ""
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
    echo -e "${COLOR_CYAN}测试套件: ${name}${COLOR_NC}"
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
}

# 结束测试套件
test_suite_end() {
    local name="$1"
    echo ""
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
    echo -e "${COLOR_CYAN}测试套件完成: ${name}${COLOR_NC}"
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
}

# 显示测试摘要
show_test_summary() {
    echo ""
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
    echo -e "${COLOR_CYAN}测试摘要${COLOR_NC}"
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
    echo -e "总测试数: ${TESTS_RUN}"
    echo -e "${COLOR_GREEN}通过: ${TESTS_PASSED}${COLOR_NC}"
    echo -e "${COLOR_RED}失败: ${TESTS_FAILED}${COLOR_NC}"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo ""
        echo -e "${COLOR_RED}失败的测�?${COLOR_NC}"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${COLOR_RED}�?{COLOR_NC} ${failed_test}"
        done
        echo ""
        echo -e "${COLOR_RED}测试结果: 失败${COLOR_NC}"
        return 1
    else
        echo ""
        echo -e "${COLOR_GREEN}测试结果: 全部通过${COLOR_NC}"
        return 0
    fi
}

# ==============================================================================
# 测试运行�?# ==============================================================================

# 运行所有测�?run_all_tests() {
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"
    echo -e "${COLOR_CYAN}Z-Panel Pro 单元测试${COLOR_NC}"
    echo -e "${COLOR_CYAN}========================================${COLOR_NC}"

    # 导入测试框架
    source "${TEST_DIR}/test_runner.sh"

    # 运行所有测试文�?    local test_files=(
        "${TEST_DIR}/test_utils.sh"
        "${TEST_DIR}/test_error_handler.sh"
        "${TEST_DIR}/test_strategy.sh"
    )

    for test_file in "${test_files[@]}"; do
        if [[ -f "${test_file}" ]]; then
            source "${test_file}"
        fi
    done

    # 显示测试摘要
    show_test_summary
}

# ==============================================================================
# 主程�?# ==============================================================================

main() {
    local test_file="${1:-}"

    if [[ -n "${test_file}" ]]; then
        # 运行指定测试文件
        if [[ -f "${TEST_DIR}/${test_file}" ]]; then
            source "${TEST_DIR}/${test_file}"
        else
            echo -e "${COLOR_RED}错误: 测试文件不存�? ${test_file}${COLOR_NC}"
            exit 1
        fi
    else
        # 运行所有测�?        run_all_tests
    fi
}

# 运行主程�?main "$@"