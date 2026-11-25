#!/usr/bin/env bash

# KCM Test Suite
# Tests core functionality and security features

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

# Test environment
TEST_DIR=$(mktemp -d)
TEST_ENV="$TEST_DIR/.env"
TEST_KEY="TEST_KCM_KEY_$$"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kcm"

# Discovery tests expect the default mode unless they set NODE_ENV themselves
unset NODE_ENV

# Cleanup function
cleanup() {
    # Remove test keys from keychain (silently)
    # Loop: a failed account test can leave two entries
    while security delete-generic-password -s "$TEST_KEY" >/dev/null 2>&1; do :; done
    security delete-generic-password -s "${TEST_KEY}_2" >/dev/null 2>&1 || true
    security delete-generic-password -s "${TEST_KEY}_QUOTE" >/dev/null 2>&1 || true
    security delete-generic-password -s "TEST_PATTERN_ONE" >/dev/null 2>&1 || true
    security delete-generic-password -s "TEST_PATTERN_TWO" >/dev/null 2>&1 || true
    security delete-generic-password -s "OTHER_PATTERN" >/dev/null 2>&1 || true

    # Remove test directory
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT INT TERM

# Test functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘${NC} $1 (skipped)"
    ((SKIPPED++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [ "$expected" = "$actual" ]; then
        pass "$test_name"
    else
        fail "$test_name - Expected: '$expected', Got: '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$test_name"
    else
        fail "$test_name - '$needle' not found in output"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$test_name"
    else
        fail "$test_name - '$needle' found in output (should not be)"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [ "$expected" -eq "$actual" ]; then
        pass "$test_name"
    else
        fail "$test_name - Expected exit code: $expected, Got: $actual"
    fi
}

# Test Suite
echo "======================================"
echo "KCM Test Suite"
echo "======================================"
echo

# Test 1: Basic help command
echo "Test Group: Basic Commands"
echo "--------------------------"
output=$("$SCRIPT_PATH" help 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Help command exits successfully"
assert_contains "$output" "kcm - Keychain Master" "Help shows title"
assert_contains "$output" "USAGE:" "Help shows usage"

# Test 2: Version command
output=$("$SCRIPT_PATH" version 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Version command exits successfully"
assert_contains "$output" "kcm version" "Version shows output"

echo
echo "Test Group: Secret Management"
echo "-----------------------------"

# Test 3: Add secret
echo "test123" | "$SCRIPT_PATH" add "$TEST_KEY" - >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Add secret via stdin"

# Test 4: Show secret
output=$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Show secret exits successfully"
assert_equals "test123" "$output" "Show returns correct secret value"

# Test 5: List secrets
output=$("$SCRIPT_PATH" ls 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "List command exits successfully"
assert_contains "$output" "$TEST_KEY" "List shows test key"

# Test 6: Remove secret
"$SCRIPT_PATH" remove "$TEST_KEY" >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Remove secret successfully"

# Multiline and shell-special secrets round-trip through add, show and use
secret=$'line "1" \\ $x\nline 2'
printf '%s' "$secret" | "$SCRIPT_PATH" add "$TEST_KEY" - >/dev/null 2>&1
output=$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1)
assert_equals "$secret" "$output" "Multiline secret shown as stored"
printf 'ML=keychain://%s\n' "$TEST_KEY" > "$TEST_DIR/ml.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/ml.env" -- bash -c 'printf "%s" "$ML"' 2>/dev/null)
assert_equals "$secret" "$output" "Multiline secret resolved by use"

# Updating an entry saved under another account replaces it instead of adding a second one
"$SCRIPT_PATH" remove "$TEST_KEY" >/dev/null 2>&1
security add-generic-password -s "$TEST_KEY" -a "kcm-test-other" -w old >/dev/null 2>&1
echo "new" | "$SCRIPT_PATH" add "$TEST_KEY" - >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Update entry with another account"
assert_equals "new" "$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1)" "Entry with another account updated"
security find-generic-password -s "$TEST_KEY" -a "$USER" >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 44 "$exit_code" "No second entry created"
"$SCRIPT_PATH" remove "$TEST_KEY" >/dev/null 2>&1

# Interactive add keeps surrounding spaces
"$SCRIPT_PATH" add "$TEST_KEY" >/dev/null 2>&1 <<< "  spaced  "
output=$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1)
assert_equals "  spaced  " "$output" "Interactive add keeps surrounding spaces"
"$SCRIPT_PATH" remove "$TEST_KEY" >/dev/null 2>&1

# Test 7: Show non-existent secret
output=$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Show non-existent secret fails"

echo
echo "Test Group: Input Validation"
echo "----------------------------"

# Test 8: Invalid key name with special characters
output=$("$SCRIPT_PATH" add '$INVALID_KEY' 2>&1 <<< "value") && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Reject key starting with $"

# Test 9: Invalid key name with numbers at start
output=$("$SCRIPT_PATH" add '123KEY' 2>&1 <<< "value") && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Reject key starting with number"

# Test 10: Valid key with underscore
echo "underscore_value" | "$SCRIPT_PATH" add "${TEST_KEY}_2" - >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Accept key with underscore"
"$SCRIPT_PATH" remove "${TEST_KEY}_2" >/dev/null 2>&1

echo
echo "Test Group: Environment File Processing"
echo "---------------------------------------"

# Test 11: Create test .env file
cat > "$TEST_ENV" << EOF
SIMPLE_VAR=simple_value
DOUBLE_QUOTED="quoted value"
SINGLE_QUOTED='single quoted'
# This is a comment
EMPTY_VAR=
  # Indented comment
SPACES_AROUND = value with spaces
EXPORT_VAR=exported
export EXPORTED_VAR=exported_value
EOF

# Add a secret for keychain:// resolution
echo "keychain_secret" | "$SCRIPT_PATH" add "${TEST_KEY}_QUOTE" - >/dev/null 2>&1

# Test 12: Process env file with keychain reference
cat >> "$TEST_ENV" << EOF
KEYCHAIN_VAR=keychain://${TEST_KEY}_QUOTE
EOF

# Test 13: Use command with env file
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$SIMPLE_VAR"' 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Use command with env file"
assert_equals "simple_value" "$output" "Simple variable resolved"

# Test 14: Quoted values
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$DOUBLE_QUOTED"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "quoted value" "$output" "Double quoted value handled"

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$SINGLE_QUOTED"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "single quoted" "$output" "Single quoted value handled"

# Test 14a: Multiline values
cat > "$TEST_ENV" << 'EOF'
MULTILINE_DOUBLE="line 1
line 2
line 3"
MULTILINE_SINGLE='single line 1
single line 2'
AFTER_MULTI=after_value
EOF

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'printf "%s" "$MULTILINE_DOUBLE"' 2>&1) && exit_code=$? || exit_code=$?
expected=$'line 1\nline 2\nline 3'
assert_equals "$expected" "$output" "Double-quoted multiline value handled"

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'printf "%s" "$MULTILINE_SINGLE"' 2>&1) && exit_code=$? || exit_code=$?
expected=$'single line 1\nsingle line 2'
assert_equals "$expected" "$output" "Single-quoted multiline value handled"

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$AFTER_MULTI"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "after_value" "$output" "Variable after multiline parsed correctly"

# Recreate test env for remaining tests
cat > "$TEST_ENV" << EOF
SIMPLE_VAR=simple_value
DOUBLE_QUOTED="quoted value"
SINGLE_QUOTED='single quoted'
# This is a comment
EMPTY_VAR=
  # Indented comment
SPACES_AROUND = value with spaces
EXPORT_VAR=exported
export EXPORTED_VAR=exported_value
EOF

# Add a secret for keychain:// resolution
echo "keychain_secret" | "$SCRIPT_PATH" add "${TEST_KEY}_QUOTE" - >/dev/null 2>&1

# Add keychain reference back
cat >> "$TEST_ENV" << EOF
KEYCHAIN_VAR=keychain://${TEST_KEY}_QUOTE
EOF

# Test 15: Keychain resolution
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$KEYCHAIN_VAR"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "keychain_secret" "$output" "Keychain reference resolved"

echo
echo "Test Group: Security Features"
echo "-----------------------------"

# Values are exported, never evaluated, so shell characters pass through literally
cat > "$TEST_ENV" << 'EOF'
DB=postgres://u:p@h/db?sslmode=require&pool=5
SUBST=$(echo bad);`echo bad`|x
EOF

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'printf "%s\n" "$DB" "$SUBST"' 2>/dev/null)
assert_equals "$(printf '%s\n' 'postgres://u:p@h/db?sslmode=require&pool=5' '$(echo bad);`echo bad`|x')" "$output" "Shell characters kept literally, never run"

output=$("$SCRIPT_PATH" use --allow-unsafe --env-file "$TEST_ENV" -- bash -c 'echo "$DB"' 2>/dev/null)
assert_equals "postgres://u:p@h/db?sslmode=require&pool=5" "$output" "--allow-unsafe still accepted"

echo
echo "Test Group: Edge Cases"
echo "----------------------"

# Test 19: Non-existent env file
output=$("$SCRIPT_PATH" use --env-file /nonexistent.env -- echo test 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Continue with non-existent env file"
assert_contains "$output" "not found" "Warning about missing file"

# Test 20: Empty env file
touch "$TEST_DIR/empty.env"
output=$("$SCRIPT_PATH" use --env-file "$TEST_DIR/empty.env" -- echo "works" 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Handle empty env file"
assert_equals "works" "$output" "Command runs with empty env"

# Test 21: Malformed env entries
cat > "$TEST_ENV" << 'EOF'
NO_EQUALS_SIGN
=NO_VAR_NAME
VAR WITH SPACES=invalid
123_STARTS_WITH_NUMBER=invalid
VALID_VAR=valid_value
EOF

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$VALID_VAR"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "valid_value" "$output" "Valid var processed despite malformed entries"

# Test 22: Command with arguments
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo $1 $2' -- "arg1" "arg2" 2>&1) && exit_code=$? || exit_code=$?
assert_equals "arg1 arg2" "$output" "Arguments passed correctly"

# A comment after a closing quote must not start a multiline value
printf 'A="x" # note\nB=after\n' > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$A|$B"' 2>/dev/null)
assert_equals "x|after" "$output" "Comment after quoted value ignored"

# A quote inside the trailing comment does not move the closing quote
printf 'A="x" # "note"\n' > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$A"' 2>/dev/null)
assert_equals "x" "$output" "Quote in trailing comment ignored"

# A comment after a multiline value closes it
printf 'A="one\ntwo" # note\nB=after\n' > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'printf "%s|%s" "$A" "$B"' 2>/dev/null)
assert_equals "$(printf 'one\ntwo|after')" "$output" "Comment after multiline value ignored"

# CRLF line endings
printf 'A="x"\r\nB=after\r\n' > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$A|$B"' 2>/dev/null)
assert_equals "x|after" "$output" "CRLF line endings handled"

# export prefix
printf 'export FOO=bar\n' > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$FOO"' 2>/dev/null)
assert_equals "bar" "$output" "export prefix accepted"

# Missing keychain entry warns and keeps the placeholder
printf 'GONE=keychain://KCM_TEST_MISSING_%s\n' "$$" > "$TEST_ENV"
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- true 2>&1)
assert_contains "$output" "KCM_TEST_MISSING_$$ not found" "Warns about missing keychain entry"

# A variable already in the environment wins over env files
printf 'FOO=file\n' > "$TEST_ENV"
output=$(FOO=shell "$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$FOO"' 2>/dev/null)
assert_equals "shell" "$output" "Environment value wins over env file"

output=$(FOO=shell-value-at-least-24-chars "$SCRIPT_PATH" use --env-file "$TEST_ENV" -s 2>/dev/null)
assert_equals "FOO=shel…hars" "$output" "Listing shows the environment value"
output=$(FOO=shell "$SCRIPT_PATH" use --env-file "$TEST_ENV" 2>/dev/null | tr -s ' ')
assert_equals "FOO environment" "$output" "Listing names the environment as source"

# No Keychain lookup for a variable the environment already sets
printf 'GONE=keychain://KCM_TEST_MISSING_%s\n' "$$" > "$TEST_ENV"
output=$(GONE=shell "$SCRIPT_PATH" use --env-file "$TEST_ENV" -- true 2>&1)
assert_not_contains "$output" "not found" "Skips Keychain lookup for variable set in environment"

# -e without a file name
output=$("$SCRIPT_PATH" use -e 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "-e without argument fails"
assert_contains "$output" "requires an argument" "-e without argument shows usage error"

echo
echo "Test Group: Env File Discovery"
echo "------------------------------"

# Monorepo layout: outside/.env must never load (above the .git root)
MONO="$TEST_DIR/outside/repo"
mkdir -p "$MONO/.git" "$MONO/apps/web"
echo "ABOVE_ROOT=leaked" > "$TEST_DIR/outside/.env"
printf 'SHARED=root\nROOT_ONLY=root\n' > "$MONO/.env"
printf 'SHARED=web\nWEB_ONLY=web\n' > "$MONO/apps/web/.env.local"

# Test 24: Merge files up to the git root, closest wins
output=$(cd "$MONO/apps/web" && "$SCRIPT_PATH" use -- bash -c 'echo "$SHARED $ROOT_ONLY $WEB_ONLY"' 2>/dev/null)
assert_equals "web root web" "$output" "Merges env files up to git root, closest wins"

# Test 25: Never read above the git root
output=$(cd "$MONO/apps/web" && "$SCRIPT_PATH" use -- bash -c 'echo "[$ABOVE_ROOT]"' 2>/dev/null)
assert_equals "[]" "$output" "Stops at git root"

# Test: Folder reached through a symlink loads files from its real parents
ln -s apps/web "$MONO/web-link"
output=$(cd "$MONO/web-link" && "$SCRIPT_PATH" use -- bash -c 'echo "$ROOT_ONLY"' 2>/dev/null)
assert_equals "root" "$output" "Symlinked folder loads real parent env files"
rm "$MONO/web-link"

# Test: No command lists names and their source, never values
output=$(cd "$MONO/apps/web" && "$SCRIPT_PATH" use 2>/dev/null) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "No command lists variables"
assert_equals "$(printf 'ROOT_ONLY ../../.env\nSHARED ./.env.local\nWEB_ONLY ./.env.local')" "$(echo "$output" | tr -s ' ')" "Lists names with winning file"
assert_not_contains "$output" "root" "Listing hides values"

# Test: --show-values masks values; --full shows them when piped
# 24 chars shows first/last 4; 23 chars is fully masked
printf 'LONG_SECRET=sk-abcdefghijklmnopq9f2c\nSHORT=abcdefghijklmnopqrstuvw\n' > "$TEST_DIR/mask.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/mask.env" --show-values 2>/dev/null)
assert_equals "$(printf 'LONG_SECRET=sk-a…9f2c\nSHORT=****')" "$output" "Show values masks values"
output=$(cd "$MONO/apps/web" && "$SCRIPT_PATH" use --full 2>/dev/null | cat)
assert_equals "$(printf 'ROOT_ONLY=root\nSHARED=web\nWEB_ONLY=web')" "$output" "--full prints merged values"

# Test: --env-file with no command lists that file only
output=$("$SCRIPT_PATH" use -e "$MONO/.env" 2>/dev/null | tr -s ' ')
assert_equals "$(printf 'ROOT_ONLY %s\nSHARED %s' "$MONO/.env" "$MONO/.env")" "$output" "Lists names from explicit env file"

# Test 26: Lists loaded files on stderr, closest first
output=$(cd "$MONO/apps/web" && "$SCRIPT_PATH" use -- true 2>&1 >/dev/null)
assert_contains "$output" "Loaded ./.env.local, ../../.env" "Shows loaded env files"

# Test: NODE_ENV=local does not load .env.local twice
output=$(cd "$MONO/apps/web" && NODE_ENV=local "$SCRIPT_PATH" use -- true 2>&1 >/dev/null)
assert_contains "$output" "Loaded ./.env.local, ../../.env" "NODE_ENV=local lists .env.local once"

# Test 27: NODE_ENV picks the mode file
echo "MODE=dev" > "$MONO/.env.development"
echo "MODE=prod" > "$MONO/.env.production"
output=$(cd "$MONO" && "$SCRIPT_PATH" use -- bash -c 'echo "$MODE"' 2>/dev/null)
assert_equals "dev" "$output" "Defaults to development mode"
output=$(cd "$MONO" && NODE_ENV=production "$SCRIPT_PATH" use -- bash -c 'echo "$MODE"' 2>/dev/null)
assert_equals "prod" "$output" "NODE_ENV=production loads .env.production"

echo
echo "Test Group: Command Help"
echo "------------------------"

# Test: --help after a command shows only that command's help
output=$("$SCRIPT_PATH" use --help 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "use --help exits 0"
assert_contains "$output" "--env-file FILE" "use --help shows use options"
assert_not_contains "$output" "add KEY_NAME" "use --help hides other commands"

output=$("$SCRIPT_PATH" rm -h 2>&1)
assert_contains "$output" "Remove a secret from Keychain" "Alias rm -h shows remove help"
assert_not_contains "$output" "show KEY_NAME" "rm -h hides other commands"

echo
echo "Test Group: Install Wrapper"
echo "---------------------------"
WRAP="$TEST_DIR/wrap-repo"
mkdir -p "$WRAP/.git" "$WRAP/apps/web"

# No answer to the prompt: default location at the git root, even from a subfolder
(cd "$WRAP/apps/web" && "$SCRIPT_PATH" install-wrapper </dev/null >/dev/null 2>&1)
output=$(PATH=/usr/bin:/bin "$WRAP/scripts/with-env" echo ran 2>&1)
assert_equals "ran" "$output" "Installs runnable wrapper at default location"

# The prompt answer sets the location
(cd "$WRAP" && echo "bin/env" | "$SCRIPT_PATH" install-wrapper >/dev/null 2>&1)
[ -x "$WRAP/bin/env" ] && pass "Installs at the location given at the prompt" || fail "Installs at the location given at the prompt"

# Never overwrites a different file
echo "mine" > "$WRAP/bin/other"
output=$(cd "$WRAP" && "$SCRIPT_PATH" install-wrapper bin/other 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Refuses to overwrite an existing file"
assert_equals "mine" "$(cat "$WRAP/bin/other")" "Existing file left unchanged"
echo
echo "Test Group: Pattern Matching"
echo "----------------------------"

# Add test secrets for pattern matching
echo "value1" | "$SCRIPT_PATH" add "TEST_PATTERN_ONE" - >/dev/null 2>&1
echo "value2" | "$SCRIPT_PATH" add "TEST_PATTERN_TWO" - >/dev/null 2>&1
echo "value3" | "$SCRIPT_PATH" add "OTHER_PATTERN" - >/dev/null 2>&1

# Test 23: List with pattern
output=$("$SCRIPT_PATH" ls "TEST_PATTERN*" 2>&1) && exit_code=$? || exit_code=$?
assert_contains "$output" "TEST_PATTERN_ONE" "Pattern matches first key"
assert_contains "$output" "TEST_PATTERN_TWO" "Pattern matches second key"
assert_not_contains "$output" "OTHER_PATTERN" "Pattern excludes non-matching"

# Cleanup pattern test keys
"$SCRIPT_PATH" remove "TEST_PATTERN_ONE" >/dev/null 2>&1
"$SCRIPT_PATH" remove "TEST_PATTERN_TWO" >/dev/null 2>&1
"$SCRIPT_PATH" remove "OTHER_PATTERN" >/dev/null 2>&1

echo
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi