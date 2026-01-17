#!/bin/bash
# ==============================================================================
# Z-Panel Pro - utils.sh 单元测试
# ==============================================================================

# 导入被测试模块
source "${SCRIPT_DIR}/../lib/utils.sh"

# ==============================================================================
# 测试验证函数
# ==============================================================================

test_validate_positive_integer() {
    test_suite_start "validate_positive_integer"

    # 测试有效输入
    assert_true "$(validate_positive_integer "1")" "Valid positive integer: 1"
    assert_true "$(validate_positive_integer "100")" "Valid positive integer: 100"
    assert_true "$(validate_positive_integer "999999")" "Valid positive integer: 999999"

    # 测试无效输入
    assert_false "$(validate_positive_integer "0")" "Invalid: 0 (not positive)"
    assert_false "$(validate_positive_integer "-1")" "Invalid: -1 (negative)"
    assert_false "$(validate_positive_integer "abc")" "Invalid: abc (not a number)"
    assert_false "$(validate_positive_integer "1.5")" "Invalid: 1.5 (decimal)"
    assert_false "$(validate_positive_integer "")" "Invalid: empty string"
    assert_false "$(validate_positive_integer " 123")" "Invalid: space before number"

    test_suite_end "validate_positive_integer"
}

test_validate_number() {
    test_suite_start "validate_number"

    # 测试有效输入
    assert_true "$(validate_number "0")" "Valid number: 0"
    assert_true "$(validate_number "1")" "Valid number: 1"
    assert_true "$(validate_number "-1")" "Valid number: -1"
    assert_true "$(validate_number "1.5")" "Valid number: 1.5"
    assert_true "$(validate_number "-1.5")" "Valid number: -1.5"

    # 测试无效输入
    assert_false "$(validate_number "abc")" "Invalid: abc (not a number)"
    assert_false "$(validate_number "")" "Invalid: empty string"
    assert_false "$(validate_number "1.2.3")" "Invalid: 1.2.3 (multiple decimals)"

    test_suite_end "validate_number"
}

test_validate_float() {
    test_suite_start "validate_float"

    # 测试有效输入
    assert_true "$(validate_float "0.0")" "Valid float: 0.0"
    assert_true "$(validate_float "1.5")" "Valid float: 1.5"
    assert_true "$(validate_float "-1.5")" "Valid float: -1.5"
    assert_true "$(validate_float "3.14159")" "Valid float: 3.14159"

    # 测试无效输入
    assert_false "$(validate_float "abc")" "Invalid: abc (not a float)"
    assert_false "$(validate_float "")" "Invalid: empty string"
    assert_false "$(validate_float "1.2.3")" "Invalid: 1.2.3 (multiple decimals)"

    test_suite_end "validate_float"
}

test_validate_filename() {
    test_suite_start "validate_filename"

    # 测试有效文件名
    assert_true "$(validate_filename "test.txt")" "Valid filename: test.txt"
    assert_true "$(validate_filename "file-123.txt")" "Valid filename: file-123.txt"
    assert_true "$(validate_filename "backup_2024.tar.gz")" "Valid filename: backup_2024.tar.gz"

    # 测试无效文件名（路径遍历攻击）
    assert_false "$(validate_filename "../etc/passwd")" "Invalid: path traversal (../)"
    assert_false "$(validate_filename "/etc/passwd")" "Invalid: absolute path"
    assert_false "$(validate_filename "file;rm -rf /")" "Invalid: command injection (;)"
    assert_false "$(validate_filename "file\`whoami\`")" "Invalid: command injection (\`)"
    assert_false "$(validate_filename "file\$(whoami)")" "Invalid: command injection (\$())"
    assert_false "$(validate_filename "file|cat")" "Invalid: command injection (|)"
    assert_false "$(validate_filename "file&&rm")" "Invalid: command injection (&&)"

    test_suite_end "validate_filename"
}

test_validate_path() {
    test_suite_start "validate_path"

    # 测试有效路径
    assert_true "$(validate_path "/tmp/test")" "Valid path: /tmp/test"
    assert_true "$(validate_path "/home/user/file.txt")" "Valid path: /home/user/file.txt"
    assert_true "$(validate_path "./relative/path")" "Valid path: ./relative/path"

    # 测试无效路径
    assert_false "$(validate_path "")" "Invalid: empty string"
    assert_false "$(validate_path "file;rm -rf /")" "Invalid: command injection"

    test_suite_end "validate_path"
}

# ==============================================================================
# 测试转换函数
# ==============================================================================

test_convert_size_to_mb() {
    test_suite_start "convert_size_to_mb"

    # 测试字节数转换
    assert_equals "1" "$(convert_size_to_mb 1048576)" "1 MB = 1048576 bytes"
    assert_equals "1024" "$(convert_size_to_mb 1073741824)" "1024 MB = 1073741824 bytes"

    # 测试KB转换
    assert_equals "1" "$(convert_size_to_mb 1024K)" "1 MB = 1024 KB"
    assert_equals "512" "$(convert_size_to_mb 524288K)" "512 MB = 524288 KB"

    # 测试MB转换
    assert_equals "100" "$(convert_size_to_mb 100M)" "100 MB"
    assert_equals "2048" "$(convert_size_to_mb 2G)" "2 GB = 2048 MB"

    # 测试GB转换
    assert_equals "1024" "$(convert_size_to_mb 1G)" "1 GB = 1024 MB"
    assert_equals "2048" "$(convert_size_to_mb 2G)" "2 GB = 2048 MB"

    test_suite_end "convert_size_to_mb"
}

test_convert_mb_to_human() {
    test_suite_start "convert_mb_to_human"

    # 测试MB转换
    assert_equals "100 MB" "$(convert_mb_to_human 100)" "100 MB"
    assert_equals "1024 MB" "$(convert_mb_to_human 1024)" "1024 MB"

    # 测试GB转换
    assert_equals "1.00 GB" "$(convert_mb_to_human 1025)" "1025 MB ≈ 1.00 GB"
    assert_equals "2.00 GB" "$(convert_mb_to_human 2048)" "2048 MB = 2.00 GB"
    assert_equals "15.62 GB" "$(convert_mb_to_human 16000)" "16000 MB ≈ 15.62 GB"

    test_suite_end "convert_mb_to_human"
}

test_calculate_percentage() {
    test_suite_start "calculate_percentage"

    # 测试百分比计算
    assert_equals "50" "$(calculate_percentage 50 100)" "50/100 = 50%"
    assert_equals "25" "$(calculate_percentage 25 100)" "25/100 = 25%"
    assert_equals "75" "$(calculate_percentage 75 100)" "75/100 = 75%"

    # 测试四舍五入
    assert_equals "33" "$(calculate_percentage 33 100)" "33/100 = 33%"
    assert_equals "67" "$(calculate_percentage 67 100)" "67/100 = 67%"

    test_suite_end "calculate_percentage"
}

test_compare_float() {
    test_suite_start "compare_float"

    # 测试相等
    assert_equals "0" "$(compare_float 1.5 1.5)" "1.5 == 1.5"

    # 测试大于
    assert_equals "1" "$(compare_float 2.5 1.5)" "2.5 > 1.5"
    assert_equals "1" "$(compare_float 1.5001 1.5)" "1.5001 > 1.5"

    # 测试小于
    assert_equals "-1" "$(compare_float 1.5 2.5)" "1.5 < 2.5"
    assert_equals "-1" "$(compare_float 1.5 1.5001)" "1.5 < 1.5001"

    test_suite_end "compare_float"
}

# ==============================================================================
# 测试字符串处理函数
# ==============================================================================

test_trim() {
    test_suite_start "trim"

    # 测试去除空格
    assert_equals "test" "$(trim "  test  ")" "Trim spaces"
    assert_equals "test" "$(trim "test")" "No spaces to trim"
    assert_equals "test string" "$(trim "  test string  ")" "Trim string with spaces"

    test_suite_end "trim"
}

test_escape_sed_pattern() {
    test_suite_start "escape_sed_pattern"

    # 测试sed特殊字符转义
    assert_equals "test\/string" "$(escape_sed_pattern "test/string")" "Escape /"
    assert_equals "test\&string" "$(escape_sed_pattern "test&string")" "Escape &"
    assert_equals "test\;string" "$(escape_sed_pattern "test;string")" "Escape ;"
    assert_equals "test\[string\]" "$(escape_sed_pattern "test[string]")" "Escape []"

    test_suite_end "escape_sed_pattern"
}

test_escape_shell_string() {
    test_suite_start "escape_shell_string"

    # 测试shell特殊字符转义
    assert_contains "$(escape_shell_string "test string")" "'" "Contains quotes"
    assert_contains "$(escape_shell_string 'test$var')" "'" "Contains quotes for $"

    test_suite_end "escape_shell_string"
}

# ==============================================================================
# 测试数组操作函数
# ==============================================================================

test_array_contains() {
    test_suite_start "array_contains"

    # 测试数组包含
    local arr=("apple" "banana" "cherry")

    assert_true "$(array_contains "apple" "${arr[@]}")" "Array contains 'apple'"
    assert_true "$(array_contains "banana" "${arr[@]}")" "Array contains 'banana'"
    assert_false "$(array_contains "orange" "${arr[@]}")" "Array does not contain 'orange'"

    test_suite_end "array_contains"
}

test_array_unique() {
    test_suite_start "array_unique"

    # 测试数组去重
    local result
    result=$(array_unique "apple" "banana" "apple" "cherry" "banana")

    assert_contains "${result}" "apple" "Result contains 'apple'"
    assert_contains "${result}" "banana" "Result contains 'banana'"
    assert_contains "${result}" "cherry" "Result contains 'cherry'"

    test_suite_end "array_unique"
}

# ==============================================================================
# 测试时间处理函数
# ==============================================================================

test_get_timestamp() {
    test_suite_start "get_timestamp"

    # 测试获取时间戳
    local timestamp
    timestamp=$(get_timestamp)

    assert_not_empty "${timestamp}" "Timestamp is not empty"
    assert_greater_than "${#timestamp}" 10 "Timestamp length > 10"

    test_suite_end "get_timestamp"
}

test_format_timestamp() {
    test_suite_start "format_timestamp"

    # 测试格式化时间戳
    local formatted
    formatted=$(format_timestamp "1704067200")

    assert_not_empty "${formatted}" "Formatted timestamp is not empty"

    test_suite_end "format_timestamp"
}

test_time_diff() {
    test_suite_start "time_diff"

    # 测试时间差计算
    local diff
    diff=$(time_diff "1704067200" "1704067260")

    assert_equals "60" "${diff}" "60 seconds difference"

    test_suite_end "time_diff"
}

# ==============================================================================
# 运行所有测试
# ==============================================================================

run_all_utils_tests() {
    # 验证函数测试
    test_validate_positive_integer
    test_validate_number
    test_validate_float
    test_validate_filename
    test_validate_path

    # 转换函数测试
    test_convert_size_to_mb
    test_convert_mb_to_human
    test_calculate_percentage
    test_compare_float

    # 字符串处理测试
    test_trim
    test_escape_sed_pattern
    test_escape_shell_string

    # 数组操作测试
    test_array_contains
    test_array_unique

    # 时间处理测试
    test_get_timestamp
    test_format_timestamp
    test_time_diff
}

# 运行测试
run_all_utils_tests