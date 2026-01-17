#!/bin/bash
# ==============================================================================
# Z-Panel Pro - strategy.sh 单元测试
# ==============================================================================

# 导入被测试模块
source "${SCRIPT_DIR}/../lib/strategy.sh"
source "${SCRIPT_DIR}/../lib/core.sh"

# 测试配置目录
readonly TEST_CONFIG_DIR="/tmp/zpanel_test_config"
mkdir -p "${TEST_CONFIG_DIR}"

# 修改配置目录用于测试
CONFIG_DIR="${TEST_CONFIG_DIR}"
STRATEGY_CONFIG_FILE="${CONFIG_DIR}/strategy.conf"

# ==============================================================================
# 测试策略验证
# ==============================================================================

test_validate_strategy_mode() {
    test_suite_start "validate_strategy_mode"

    # 测试有效的策略模式
    assert_true "$(validate_strategy_mode "conservative")" "Valid: conservative"
    assert_true "$(validate_strategy_mode "balance")" "Valid: balance"
    assert_true "$(validate_strategy_mode "aggressive")" "Valid: aggressive"

    # 测试无效的策略模式
    assert_false "$(validate_strategy_mode "invalid")" "Invalid: invalid"
    assert_false "$(validate_strategy_mode "conservative-mode")" "Invalid: conservative-mode"
    assert_false "$(validate_strategy_mode "")" "Invalid: empty string"

    test_suite_end "validate_strategy_mode"
}

# ==============================================================================
# 测试策略参数计算
# ==============================================================================

test_calculate_strategy() {
    test_suite_start "calculate_strategy"

    # 测试保守模式
    local conservative_params
    conservative_params=$(calculate_strategy "conservative")

    assert_contains "${conservative_params}" "zram_size_mb" "Conservative has zram_size_mb"
    assert_contains "${conservative_params}" "swap_size_mb" "Conservative has swap_size_mb"
    assert_contains "${conservative_params}" "swappiness" "Conservative has swappiness"

    # 测试平衡模式
    local balance_params
    balance_params=$(calculate_strategy "balance")

    assert_contains "${balance_params}" "zram_size_mb" "Balance has zram_size_mb"
    assert_contains "${balance_params}" "swap_size_mb" "Balance has swap_size_mb"
    assert_contains "${balance_params}" "swappiness" "Balance has swappiness"

    # 测试激进模式
    local aggressive_params
    aggressive_params=$(calculate_strategy "aggressive")

    assert_contains "${aggressive_params}" "zram_size_mb" "Aggressive has zram_size_mb"
    assert_contains "${aggressive_params}" "swap_size_mb" "Aggressive has swap_size_mb"
    assert_contains "${aggressive_params}" "swappiness" "Aggressive has swappiness"

    test_suite_end "calculate_strategy"
}

# ==============================================================================
# 测试策略描述
# ==============================================================================

test_get_strategy_description() {
    test_suite_start "get_strategy_description"

    # 测试保守模式描述
    local conservative_desc
    conservative_desc=$(get_strategy_description "conservative")
    assert_not_empty "${conservative_desc}" "Conservative description not empty"

    # 测试平衡模式描述
    local balance_desc
    balance_desc=$(get_strategy_description "balance")
    assert_not_empty "${balance_desc}" "Balance description not empty"

    # 测试激进模式描述
    local aggressive_desc
    aggressive_desc=$(get_strategy_description "aggressive")
    assert_not_empty "${aggressive_desc}" "Aggressive description not empty"

    test_suite_end "get_strategy_description"
}

test_get_strategy_details() {
    test_suite_start "get_strategy_details"

    # 测试策略详情
    local details
    details=$(get_strategy_details "balance")

    assert_not_empty "${details}" "Strategy details not empty"
    assert_contains "${details}" "zram" "Details contain zram"
    assert_contains "${details}" "swap" "Details contain swap"

    test_suite_end "get_strategy_details"
}

# ==============================================================================
# 测试策略配置保存和加载
# ==============================================================================

test_save_and_load_strategy_config() {
    test_suite_start "save_and_load_strategy_config"

    # 清除之前的配置
    rm -f "${STRATEGY_CONFIG_FILE}"

    # 保存策略配置
    save_strategy_config "balance"
    assert_file_exists "${STRATEGY_CONFIG_FILE}" "Strategy config file created"

    # 加载策略配置
    local loaded_mode
    source "${STRATEGY_CONFIG_FILE}"
    loaded_mode="${STRATEGY_MODE:-}"

    assert_equals "balance" "${loaded_mode}" "Loaded strategy mode matches saved"

    # 清理
    rm -f "${STRATEGY_CONFIG_FILE}"

    test_suite_end "save_and_load_strategy_config"
}

# ==============================================================================
# 测试策略模式设置和获取
# ==============================================================================

test_set_and_get_strategy_mode() {
    test_suite_start "set_and_get_strategy_mode"

    # 清除之前的配置
    rm -f "${STRATEGY_CONFIG_FILE}"

    # 设置策略模式
    set_strategy_mode "conservative"

    # 获取策略模式
    local mode
    mode=$(get_strategy_mode)

    assert_equals "conservative" "${mode}" "Strategy mode matches set value"

    # 切换到平衡模式
    set_strategy_mode "balance"
    mode=$(get_strategy_mode)

    assert_equals "balance" "${mode}" "Strategy mode switched to balance"

    # 清理
    rm -f "${STRATEGY_CONFIG_FILE}"

    test_suite_end "set_and_get_strategy_mode"
}

# ==============================================================================
# 测试可用策略列表
# ==============================================================================

test_get_available_strategies() {
    test_suite_start "get_available_strategies"

    # 获取可用策略
    local strategies
    strategies=$(get_available_strategies)

    assert_not_empty "${strategies}" "Available strategies not empty"
    assert_contains "${strategies}" "conservative" "Contains conservative"
    assert_contains "${strategies}" "balance" "Contains balance"
    assert_contains "${strategies}" "aggressive" "Contains aggressive"

    test_suite_end "get_available_strategies"
}

# ==============================================================================
# 测试策略常量
# ==============================================================================

test_strategy_constants() {
    test_suite_start "策略常量"

    # 测试策略常量
    assert_equals "conservative" "${STRATEGY_CONSERVATIVE}" "Conservative constant"
    assert_equals "balance" "${STRATEGY_BALANCE}" "Balance constant"
    assert_equals "aggressive" "${STRATEGY_AGGRESSIVE}" "Aggressive constant"

    test_suite_end "策略常量"
}

# ==============================================================================
# 运行所有测试
# ==============================================================================

run_all_strategy_tests() {
    # 策略验证测试
    test_validate_strategy_mode
    test_strategy_constants

    # 策略参数计算测试
    test_calculate_strategy

    # 策略描述测试
    test_get_strategy_description
    test_get_strategy_details

    # 策略配置测试
    test_save_and_load_strategy_config

    # 策略模式设置测试
    test_set_and_get_strategy_mode

    # 可用策略列表测试
    test_get_available_strategies
}

# 运行测试
run_all_strategy_tests