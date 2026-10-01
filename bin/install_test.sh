#!/bin/bash
TEST_ENV_HANDOFF_GOMODCACHE=1
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-env.sh"
test_env_enter "$0" "$@"
# install_test.sh - Tests for install.sh functions
# Run with: bash bin/install_test.sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_empty() {
    local value="$1"
    local message="$2"

    if [ -n "$value" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: $message (value is empty)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_file_exists() {
    local file="$1"
    local message="$2"

    if [ -f "$file" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: $message (file not found: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Setup: detect platform (inline version)
detect_platform() {
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local arch="$(uname -m)"

    case "$os" in
        darwin) PLATFORM="darwin" ;;
        linux) PLATFORM="linux" ;;
        mingw*|msys*|cygwin*) PLATFORM="windows" ;;
        *) PLATFORM="unknown" ;;
    esac

    case "$arch" in
        x86_64|amd64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) ARCH="unknown" ;;
    esac

    if [ "$PLATFORM" = "windows" ]; then
        BINARY_NAME="claude-notifications-${PLATFORM}-${ARCH}.exe"
    else
        BINARY_NAME="claude-notifications-${PLATFORM}-${ARCH}"
    fi
}

# ============= Tests =============

echo ""
echo "========================================="
echo " Running install.sh Tests"
echo "========================================="
echo ""

if command -v go >/dev/null 2>&1; then
    assert_equals "off" "$(go env GOPROXY)" "Isolated Go builds use GOPROXY=off"
    assert_equals "local" "$(go env GOTOOLCHAIN)" "Isolated Go builds pin GOTOOLCHAIN=local"
fi

# Test 1: Platform detection
echo "--- Test: Platform Detection ---"
detect_platform

current_os="$(uname -s | tr '[:upper:]' '[:lower:]')"

case "$current_os" in
    darwin)
        assert_equals "darwin" "$PLATFORM" "Platform should be darwin on macOS"
        ;;
    linux)
        assert_equals "linux" "$PLATFORM" "Platform should be linux on Linux"
        ;;
    mingw*|msys*|cygwin*)
        assert_equals "windows" "$PLATFORM" "Platform should be windows on Windows"
        ;;
esac

assert_not_empty "$ARCH" "Architecture should be detected"
assert_not_empty "$BINARY_NAME" "Binary name should be constructed"

# Binary name should contain platform and arch
if [[ "$BINARY_NAME" == *"$PLATFORM"* ]] && [[ "$BINARY_NAME" == *"$ARCH"* ]]; then
    echo -e "${GREEN}PASS${NC}: Binary name contains platform and arch"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}: Binary name should contain platform and arch"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# Test 2: Architecture detection
echo "--- Test: Architecture Detection ---"
current_arch="$(uname -m)"

case "$current_arch" in
    x86_64|amd64)
        assert_equals "amd64" "$ARCH" "Architecture should be amd64 for x86_64"
        ;;
    arm64|aarch64)
        assert_equals "arm64" "$ARCH" "Architecture should be arm64 for arm64/aarch64"
        ;;
esac
echo ""

# Test 3: Binary name format
echo "--- Test: Binary Name Format ---"

if [ "$PLATFORM" = "windows" ]; then
    if [[ "$BINARY_NAME" == *.exe ]]; then
        echo -e "${GREEN}PASS${NC}: Windows binary has .exe extension"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: Windows binary should have .exe extension"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    if [[ "$BINARY_NAME" != *.exe ]]; then
        echo -e "${GREEN}PASS${NC}: Unix binary has no .exe extension"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: Unix binary should not have .exe extension"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi
echo ""

# Test 4: install.sh exists and is executable
echo "--- Test: install.sh exists ---"
assert_file_exists "${SCRIPT_DIR}/install.sh" "install.sh should exist"

if [ -x "${SCRIPT_DIR}/install.sh" ]; then
    echo -e "${GREEN}PASS${NC}: install.sh is executable"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}: install.sh should be executable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# Test 5: Wrapper script exists
echo "--- Test: Wrapper script exists ---"
if [ "$PLATFORM" = "windows" ]; then
    # On Windows, wrapper is a .bat file (may not exist until install.sh is run)
    # Skip this test on Windows CI where install.sh hasn't been run
    if [ -f "${SCRIPT_DIR}/claude-notifications.bat" ]; then
        assert_file_exists "${SCRIPT_DIR}/claude-notifications.bat" "Wrapper script should exist (.bat)"
    else
        echo -e "${YELLOW}SKIP${NC}: Wrapper script test (install.sh not run yet)"
    fi
elif [ -e "${SCRIPT_DIR}/claude-notifications" ]; then
    assert_file_exists "${SCRIPT_DIR}/claude-notifications" "Wrapper script should exist"
else
    echo -e "${YELLOW}SKIP${NC}: Generated wrapper (install.sh not run yet)"
fi
echo ""

# Test 6: All supported platforms
echo "--- Test: Supported Platform Combinations ---"

platforms=("darwin-amd64" "darwin-arm64" "linux-amd64" "linux-arm64" "windows-amd64")

for combo in "${platforms[@]}"; do
    platform=$(echo "$combo" | cut -d'-' -f1)
    arch=$(echo "$combo" | cut -d'-' -f2)

    if [ "$platform" = "windows" ]; then
        expected_name="claude-notifications-${platform}-${arch}.exe"
    else
        expected_name="claude-notifications-${platform}-${arch}"
    fi

    if [[ "$expected_name" == "claude-notifications-"* ]]; then
        echo -e "${GREEN}PASS${NC}: $combo -> $expected_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: Invalid name format for $combo"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done
echo ""

# Test 7: terminal-notifier URL format
echo "--- Test: terminal-notifier URL ---"
notifier_url="https://github.com/julienXX/terminal-notifier/releases/download/2.0.0/terminal-notifier-2.0.0.zip"

if [[ "$notifier_url" == "https://github.com/"* ]] && [[ "$notifier_url" == *".zip" ]]; then
    echo -e "${GREEN}PASS${NC}: terminal-notifier URL format is valid"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}: terminal-notifier URL format is invalid"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# Test 8: GitHub repo URL format
echo "--- Test: GitHub Repo URL ---"
repo="777genius/agent-notifications"
release_url="https://github.com/${repo}/releases/latest/download"

if [[ "$release_url" == "https://github.com/"* ]] && [[ "$release_url" == *"/releases/"* ]]; then
    echo -e "${GREEN}PASS${NC}: GitHub release URL format is valid"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}: GitHub release URL format is invalid"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# WSL mount fallback. Source the installer with its final main call removed and
# mock uname, grep, and [ inside child processes. Children never create /mnt/c
# or read /proc; unrelated [ checks delegate to builtin [.
WSL_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wsl-install-tests.XXXXXX") || WSL_TEST_ROOT=""
if [ -z "$WSL_TEST_ROOT" ]; then
    echo -e "${RED}FAIL${NC}: could not create WSL detection sandbox"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    sed '/^main "\$@"$/d' "$SCRIPT_DIR/install.sh" > "$WSL_TEST_ROOT/functions.sh"
    cat > "$WSL_TEST_ROOT/probe.sh" <<'WSL_PROBE'
source "$WSL_FUNCTIONS_SH" || exit 97

uname() {
    if builtin [ "${1:-}" = "-s" ]; then
        printf '%s\n' "$WSL_SCENARIO_OS"
        return 0
    fi
    command uname "$@" || return $?
    return 0
}

grep() {
    local arg saw_proc=0
    if builtin [ "$#" -eq 0 ]; then
        return 1
    fi
    for arg in "$@"; do
        if builtin [ "$arg" = "/proc/version" ]; then
            saw_proc=1
        fi
    done
    if builtin [ "$saw_proc" -eq 1 ]; then
        if builtin [ "$#" -eq 3 ] && builtin [ "$1" = "-qiE" ] && builtin [ "$2" = "microsoft|wsl" ] && builtin [ "$3" = "/proc/version" ]; then
            if builtin [ "$WSL_SCENARIO_KERNEL" = "unavailable" ]; then
                return 2
            fi
            if printf '%s\n' "$WSL_SCENARIO_KERNEL_TEXT" | command grep -qiE 'microsoft|wsl'; then
                return 0
            fi
            return 1
        fi
        printf 'UNEXPECTED_PROC_GREP\n' >&2
        return 1
    fi
    command grep "$@" || return $?
    return 0
}

# Shadow the [ builtin only for the simulated WSL probes.
[() {
    if builtin [ "$#" -eq 3 ] && builtin [ "$3" = "]" ]; then
        if builtin [ "$2" = "/mnt/c" ]; then
            case "$1" in
                -d)
                    if builtin [ "$WSL_SCENARIO_MNT" = "dir" ]; then
                        return 0
                    fi
                    return 1
                    ;;
                -f)
                    if builtin [ "$WSL_SCENARIO_MNT" = "file" ]; then
                        return 0
                    fi
                    return 1
                    ;;
                -e|-r|-s)
                    if builtin [ "$WSL_SCENARIO_MNT" = "dir" ] || builtin [ "$WSL_SCENARIO_MNT" = "file" ]; then
                        return 0
                    fi
                    return 1
                    ;;
                *)
                    return 1
                    ;;
            esac
        fi
        if builtin [ "$2" = "/proc/version" ]; then
            case "$1" in
                -d)
                    return 1
                    ;;
                -e|-f|-r|-s)
                    if builtin [ "$WSL_SCENARIO_KERNEL" = "unavailable" ]; then
                        return 1
                    fi
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
        fi
    fi
    if builtin [ "$@"; then
        return 0
    fi
    return 1
}

if builtin [ "$WSL_SCENARIO_MODE" = "main" ]; then
    check_required_tools() {
        printf 'PREFLIGHT_REACHED\n'
        exit 86
    }
    main
    printf 'MAIN_RETURNED\n'
    exit 0
fi

if is_wsl_environment; then
    printf 'DETECTED\n'
else
    printf 'CLEAR\n'
fi
abort_if_wsl_environment
printf 'ABORT_RETURNED\n'
WSL_PROBE

    wsl_assert_case() {
        local name="$1"
        local expect="$2"
        local mode="$3"
        local status="$4"
        local output="$5"
        local target="$6"
        local ok=0 extras="" entry

        if [ -e "$target/.install.lock" ]; then
            extras="lock created"
        fi
        entry=$(ls -A "$target" 2>/dev/null || true)
        if [ -n "$entry" ]; then
            extras="${extras} install target not empty"
        fi

        if [ "$mode" = "main" ]; then
            if [ "$status" -eq 1 ] \
                && [[ "$output" == *"WSL environment detected"* ]] \
                && [[ "$output" == *"Git Bash"* ]] \
                && [[ "$output" == *"PowerShell or Windows Terminal"* ]] \
                && [[ "$output" == *"https://777genius.github.io/agent-notifications/#install"* ]] \
                && [[ "$output" != *"PREFLIGHT_REACHED"* ]] \
                && [[ "$output" != *"Platform:"* ]] \
                && [[ "$output" != *"MAIN_RETURNED"* ]] \
                && [ -z "$extras" ]; then
                ok=1
            fi
        elif [ "$expect" = "DETECTED" ]; then
            if [ "$status" -eq 1 ] \
                && [[ "$output" == *"DETECTED"* ]] \
                && [[ "$output" != *"CLEAR"* ]] \
                && [[ "$output" == *"WSL environment detected"* ]] \
                && [[ "$output" == *"Git Bash"* ]] \
                && [[ "$output" == *"PowerShell or Windows Terminal"* ]] \
                && [[ "$output" == *"https://777genius.github.io/agent-notifications/#install"* ]] \
                && [[ "$output" != *"ABORT_RETURNED"* ]] \
                && [ -z "$extras" ]; then
                ok=1
            fi
        elif [ "$status" -eq 0 ] \
            && [[ "$output" == *"CLEAR"* ]] \
            && [[ "$output" == *"ABORT_RETURNED"* ]] \
            && [[ "$output" != *"DETECTED"* ]] \
            && [[ "$output" != *"WSL environment detected"* ]] \
            && [ -z "$extras" ]; then
            ok=1
        fi

        if [ "$ok" -eq 1 ]; then
            echo -e "${GREEN}PASS${NC}: $name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC}: $name"
            echo "  status: $status"
            if [ -n "$extras" ]; then
                echo "  $extras"
            fi
            echo "  output:"
            printf '%s\n' "$output" | sed 's/^/    /'
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    }

    wsl_case() {
        local name="$1"
        local expect="$2"
        local mode="$3"
        local os="$4"
        local distro="$5"
        local interop="$6"
        local kernel="$7"
        local kernel_text="$8"
        local mnt="$9"
        local allow="${10}"
        local output status target
        WSL_CASE_SEQ=$((WSL_CASE_SEQ + 1))
        target="$WSL_TEST_ROOT/target-$WSL_CASE_SEQ"
        mkdir -p "$target" || {
            echo -e "${RED}FAIL${NC}: $name (sandbox)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return
        }

        output=$(
            unset WSL_DISTRO_NAME WSL_INTEROP CLAUDE_NOTIFICATIONS_ALLOW_WSL
            INSTALL_TARGET_DIR="$target"
            WSL_FUNCTIONS_SH="$WSL_TEST_ROOT/functions.sh"
            WSL_SCENARIO_OS="$os"
            WSL_SCENARIO_KERNEL="$kernel"
            WSL_SCENARIO_KERNEL_TEXT="$kernel_text"
            WSL_SCENARIO_MNT="$mnt"
            WSL_SCENARIO_MODE="$mode"
            export INSTALL_TARGET_DIR WSL_FUNCTIONS_SH WSL_SCENARIO_OS \
                WSL_SCENARIO_KERNEL WSL_SCENARIO_KERNEL_TEXT WSL_SCENARIO_MNT \
                WSL_SCENARIO_MODE
            if [ "$distro" != "__UNSET__" ]; then
                WSL_DISTRO_NAME="$distro"
                export WSL_DISTRO_NAME
            fi
            if [ "$interop" != "__UNSET__" ]; then
                WSL_INTEROP="$interop"
                export WSL_INTEROP
            fi
            if [ "$allow" != "__UNSET__" ]; then
                CLAUDE_NOTIFICATIONS_ALLOW_WSL="$allow"
                export CLAUDE_NOTIFICATIONS_ALLOW_WSL
            fi
            bash --noprofile --norc "$WSL_TEST_ROOT/probe.sh" 2>&1
        )
        status=$?
        wsl_assert_case "$name" "$expect" "$mode" "$status" "$output" "$target"
    }

    wsl_mount_case() {
        local name="$1"
        local expect="$2"
        local mode="$3"
        local kernel="$4"
        local mnt="$5"
        local kernel_text="$6"
        wsl_case "$name" "$expect" "$mode" "Linux" "__UNSET__" "__UNSET__" \
            "$kernel" "$kernel_text" "$mnt" "__UNSET__"
    }

    wsl_all_signals_case() {
        local name="$1"
        local expect="$2"
        local os="$3"
        local allow="$4"
        wsl_case "$name" "$expect" "detect-abort" "$os" \
            "Ubuntu" "/run/WSL/9_interop" "readable" \
            "Linux version 5.15.153.1-microsoft-standard-WSL2" \
            "dir" "$allow"
    }

    echo "--- Test: WSL Windows drive mount detection ---"
    if grep -qx 'main "$@"' "$WSL_TEST_ROOT/functions.sh"; then
        echo -e "${RED}FAIL${NC}: sourced installer still invokes main"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    elif ! bash -n "$WSL_TEST_ROOT/probe.sh"; then
        echo -e "${RED}FAIL${NC}: WSL probe failed bash -n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        WSL_CASE_SEQ=0
        negative_kernel="Linux version 6.8.0-100-generic"
        wsl_mount_case "Linux /mnt/c directory and negative kernel probe aborts with Git Bash guidance" \
            DETECTED detect-abort readable dir "$negative_kernel"
        wsl_mount_case "Linux /mnt/c directory and unavailable kernel probe aborts with Git Bash guidance" \
            DETECTED detect-abort unavailable dir ""
        wsl_mount_case "main rejects /mnt/c before preflight when the kernel probe is negative" \
            DETECTED main readable dir "$negative_kernel"
        wsl_mount_case "main rejects /mnt/c before preflight when the kernel probe is unavailable" \
            DETECTED main unavailable dir ""
        wsl_mount_case "Linux with no /mnt/c and no other WSL evidence continues" \
            CLEAR detect-abort readable absent "$negative_kernel"
        wsl_mount_case "Linux with an unavailable kernel probe and no /mnt/c continues" \
            CLEAR detect-abort unavailable absent ""
        wsl_mount_case "regular file at /mnt/c is not a WSL directory" \
            CLEAR detect-abort readable file "$negative_kernel"
        wsl_mount_case "regular file at /mnt/c with an unavailable kernel probe continues" \
            CLEAR detect-abort unavailable file ""
        wsl_mount_case "kernel text Windows without Microsoft or WSL is not WSL" \
            CLEAR detect-abort readable absent "Linux version 6.1.0-windows"

        wsl_case "WSL_DISTRO_NAME detects WSL without /mnt/c" \
            DETECTED detect-abort Linux Ubuntu __UNSET__ unavailable "" absent __UNSET__
        wsl_case "WSL_INTEROP detects WSL without /mnt/c" \
            DETECTED detect-abort Linux __UNSET__ /run/WSL/9_interop unavailable "" absent __UNSET__

        kernel_text=""
        for kernel_text in Microsoft microsoft MICROSOFT MiCrOsOfT WSL wsl wSl \
            "Linux version 5.15.153.1-microsoft-standard-WSL2"; do
            wsl_case "kernel probe matches '$kernel_text' without /mnt/c" \
                DETECTED detect-abort Linux __UNSET__ __UNSET__ readable "$kernel_text" absent __UNSET__
        done

        allow_value=""
        for allow_value in 1 true TRUE yes YES; do
            wsl_all_signals_case "override $allow_value skips detection when every WSL signal is present" \
                CLEAR Linux "$allow_value"
        done
        for allow_value in __UNSET__ "" false 0 no Yes; do
            allow_label="$allow_value"
            if [ "$allow_value" = "__UNSET__" ]; then
                allow_label="unset"
            elif [ -z "$allow_value" ]; then
                allow_label="empty"
            fi
            wsl_all_signals_case "override $allow_label does not bypass detection" \
                DETECTED Linux "$allow_value"
        done

        wsl_all_signals_case "macOS stays outside the WSL guard with mount evidence and WSL variables" \
            CLEAR Darwin __UNSET__
        wsl_all_signals_case "Git Bash MINGW stays outside the WSL guard with mount evidence and WSL variables" \
            CLEAR "MINGW64_NT-10.0-22631" __UNSET__
        wsl_all_signals_case "MSYS stays outside the WSL guard with mount evidence and WSL variables" \
            CLEAR "MSYS_NT-10.0-22631" __UNSET__
        wsl_all_signals_case "MinGW32 stays outside the WSL guard with mount evidence and WSL variables" \
            CLEAR "MINGW32_NT-6.1" __UNSET__
    fi
    rm -rf "$WSL_TEST_ROOT"
fi
echo ""

# Discover the disposable product-isolation regression in the existing CI entrypoint.
if bash "$SCRIPT_DIR/codex-hook-wrapper_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/install_config_preflight_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/install_config_native_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/install_transaction_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/bootstrap_product_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/installer_runtime_fallback_e2e_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if bash "$SCRIPT_DIR/agent-launcher_test.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Summary
echo "========================================="
echo " Test Summary"
echo "========================================="
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
