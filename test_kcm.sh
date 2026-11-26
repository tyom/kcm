#!/usr/bin/env bash

# KCM Test Suite
# Tests core functionality and security features

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0

# Test environment
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/TEST_KCM_KEY_XXXXXXXXXX") || exit 1
TEST_ENV="$TEST_DIR/.env"
TEST_KEY="${TEST_DIR##*/}"
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
    security delete-generic-password -s "${TEST_KEY}_TEST_PATTERN_ONE" >/dev/null 2>&1 || true
    security delete-generic-password -s "${TEST_KEY}_TEST_PATTERN_TWO" >/dev/null 2>&1 || true
    security delete-generic-password -s "${TEST_KEY}_OTHER_PATTERN" >/dev/null 2>&1 || true
    for suffix in SHARED COLLISION; do
        while security delete-generic-password -s "${TEST_KEY}_$suffix" >/dev/null 2>&1; do :; done
    done
    security delete-generic-password -s "NEXT_PUBLIC_${TEST_KEY}_KEY" >/dev/null 2>&1 || true
    for suffix in API_KEY MULTI CLASH RENAMED LEGACY OTHER_APP INJECTED LINK_KEY NL_KEY MOVED_KEY RO_KEY REF_KEY LONG DUP_KEY MID_KEY EXPORT HINT ACCENT; do
        security delete-generic-password -s "${TEST_KEY}_$suffix" >/dev/null 2>&1 || true
    done

    # Remove test directory
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# Test functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
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

# Drop colour and cursor escape codes, and the carriage returns a pty adds
strip_ansi() {
    sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' | tr -d '\r'
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

# Piped help stays plain text for scripts; in a terminal it is coloured
output=$("$SCRIPT_PATH" help 2>&1)
assert_not_contains "$output" $'\033' "Piped help has no colour codes"
output=$(NO_COLOR='' script -q /dev/null "$SCRIPT_PATH" help </dev/null 2>&1)
assert_contains "$output" $'\033[1;38;5;234;48;5;250m add ' "Help in a terminal shows commands as chips"

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

# kcm marks its entries so they stand out in Keychain Access
attrs=$(security find-generic-password -s "$TEST_KEY" 2>&1)
assert_contains "$attrs" '"desc"<blob>="kcm secret"' "Added secret has kind 'kcm secret'"
assert_contains "$attrs" '"crtr"<uint32>="kcm "' "Added secret has creator code 'kcm '"
assert_contains "$attrs" '"icmt"<blob>="Added by kcm"' "Added secret has a comment"

# -c stores a hint as the comment, before or after the -
echo "hinted" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "Stripe test key from the dashboard" >/dev/null 2>&1
attrs=$(security find-generic-password -s "${TEST_KEY}_HINT" 2>&1)
assert_contains "$attrs" '"icmt"<blob>="Stripe test key from the dashboard"' "add -c stores the hint as the comment"

# A new value without -c keeps the hint
echo "hinted2" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - >/dev/null 2>&1
attrs=$(security find-generic-password -s "${TEST_KEY}_HINT" 2>&1)
assert_contains "$attrs" '"icmt"<blob>="Stripe test key from the dashboard"' "Re-adding without -c keeps the hint"
assert_equals "hinted2" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "Re-adding without -c still updates the value"

# A long hint would push the value off stdin and onto the argument list
long_hint=$(head -c 201 /dev/zero | tr '\0' 'h')
output=$(echo "hinted3" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "$long_hint" 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "add -c refuses a hint over 200 characters"
assert_equals "hinted2" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "A refused hint leaves the value alone"

# security -i cuts a line at 4095 bytes, not characters: 200 emoji are 800 bytes
emoji_hint=$(printf '🙂%.0s' $(seq 200))
big_value=$(head -c 1700 /dev/zero | tr '\0' 'v')
echo "$big_value" | LC_ALL=en_US.UTF-8 "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "$emoji_hint" >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "add stores a value whose command is under 4096 characters but over 4095 bytes"
assert_equals "$big_value" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "A long non-ASCII hint does not cut the value short"
echo "hinted2" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "Stripe test key from the dashboard" >/dev/null 2>&1

# ls shows hints next to names, but not kcm's own comments
output=$("$SCRIPT_PATH" ls "${TEST_KEY}*" 2>&1 | strip_ansi | tr -s ' ')
assert_contains "$output" "${TEST_KEY}_HINT Stripe test key from the dashboard" "ls shows the hint"
assert_not_contains "$output" "Added by kcm" "ls hides kcm's own comment"
echo "hinted4" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "clé d'été" >/dev/null 2>&1
assert_contains "$("$SCRIPT_PATH" ls "${TEST_KEY}_HINT" 2>&1 | strip_ansi | tr -s ' ')" "${TEST_KEY}_HINT clé d'été" "ls shows a hint with accented letters"

# Test 4: Show secret
output=$("$SCRIPT_PATH" show "$TEST_KEY" 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Show secret exits successfully"
assert_equals "test123" "$output" "Show returns correct secret value"

# If the old hint can't be read, a new value must not replace it with kcm's default comment
mkdir -p "$TEST_DIR/failcomment"
cat > "$TEST_DIR/failcomment/security" << 'EOF'
#!/bin/bash
# Fail the attribute lookup for one account: no -g and no -i, so reads and writes still work
if [ "${1:-}" = find-generic-password ] && [[ " $* " == *" -a "* && " $* " != *" -g "* ]]; then exit 1; fi
exec /usr/bin/security "$@"
EOF
chmod +x "$TEST_DIR/failcomment/security"
echo "hinted4" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "Keep me" >/dev/null 2>&1
echo "hinted5" | PATH="$TEST_DIR/failcomment:$PATH" "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "add fails when the old hint can't be read"
assert_contains "$(security find-generic-password -s "${TEST_KEY}_HINT" 2>&1)" '"icmt"<blob>="Keep me"' "A failed hint lookup leaves the hint alone"
assert_equals "hinted4" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "A failed hint lookup leaves the value alone"

# A comment with newlines, as Keychain Access can write, survives a new value byte for byte
security add-generic-password -U -s "${TEST_KEY}_HINT" -a "$USER" -j $'Dashboard\nRotate monthly\n' -w multiline >/dev/null 2>&1
echo "hinted7" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - >/dev/null 2>&1
assert_contains "$(security find-generic-password -s "${TEST_KEY}_HINT" 2>&1)" '"icmt"<blob>=0x44617368626F6172640A526F74617465206D6F6E74686C790A ' "Re-adding without -c leaves a multi-line comment unchanged"
assert_equals "hinted7" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "Re-adding next to a multi-line comment updates the value"

# security -i exits 0 when its command fails; the same value with a new hint must not pass as stored
mkdir -p "$TEST_DIR/nowrite"
cat > "$TEST_DIR/nowrite/security" << 'EOF'
#!/bin/bash
# Drop every write: -i reads the command and does nothing, add-generic-password does nothing
if [ "${1:-}" = -i ]; then cat >/dev/null; exit 0; fi
[ "${1:-}" = add-generic-password ] && exit 0
exec /usr/bin/security "$@"
EOF
chmod +x "$TEST_DIR/nowrite/security"
echo "hinted7" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "Old hint" >/dev/null 2>&1
echo "hinted7" | PATH="$TEST_DIR/nowrite:$PATH" "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "New hint" >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "add fails when the hint was not stored, even if the value matches"

# kcm tells its own comments from a hint by their wording, so a hint may not use it
echo "hinted8" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "Kept hint" >/dev/null 2>&1
# A newline is stored as a space, so the check must see the hint as it will be stored
for reserved in "Imported by kcm from a legacy vault" "Added by kcm" $'Imported by\nkcm from a legacy vault' $'Added by\nkcm'; do
    echo "hinted9" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c "$reserved" >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_exit_code 1 "$exit_code" "add -c refuses the hint '${reserved//$'\n'/<newline>}'"
done
assert_equals "hinted8" "$("$SCRIPT_PATH" show "${TEST_KEY}_HINT" 2>&1)" "A refused reserved hint leaves the value alone"
assert_contains "$(security find-generic-password -s "${TEST_KEY}_HINT" 2>&1)" '"icmt"<blob>="Kept hint"' "A refused reserved hint leaves the old hint alone"

# A hint can hold escape codes, written by kcm or another tool; ls must not send them to the terminal
echo "hinted5" | "$SCRIPT_PATH" add "${TEST_KEY}_HINT" - -c $'bad\033[2Jhint' >/dev/null 2>&1
assert_not_contains "$("$SCRIPT_PATH" ls "${TEST_KEY}_HINT" 2>&1 | grep "${TEST_KEY}_HINT  ")" $'\033[2J' "ls strips control characters from a hint"

# Test 5: List secrets
output=$("$SCRIPT_PATH" ls 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "List command exits successfully"
assert_contains "$output" "$TEST_KEY" "List shows test key"

# A keychain that can't be dumped makes ls fail instead of printing a partial list
mkdir -p "$TEST_DIR/faildump"
cat > "$TEST_DIR/faildump/security" << 'EOF'
#!/bin/bash
[ "${1:-}" = dump-keychain ] && exit 1
exec /usr/bin/security "$@"
EOF
chmod +x "$TEST_DIR/faildump/security"
PATH="$TEST_DIR/faildump:$PATH" "$SCRIPT_PATH" ls >/dev/null 2>&1 && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "List fails when a keychain can't be read"

# ls shows kcm's entries, then untagged ones from older kcm versions, and hides other apps' entries
security add-generic-password -s "${TEST_KEY}_LEGACY" -a "$USER" -w old >/dev/null 2>&1
security add-generic-password -s "${TEST_KEY}_OTHER_APP" -a "some-app" -w x >/dev/null 2>&1
output=$("$SCRIPT_PATH" ls "${TEST_KEY}*" 2>&1 | strip_ansi)
kcm_part="${output%%older kcm*}"
legacy_part="${output#*older kcm}"
assert_contains "$kcm_part" "• $TEST_KEY"$'\n' "List shows kcm entries first"
assert_not_contains "$kcm_part" "${TEST_KEY}_LEGACY" "List keeps untagged entries out of the kcm group"
assert_contains "$legacy_part" "• ${TEST_KEY}_LEGACY" "List shows untagged entries from older kcm separately"
assert_not_contains "$output" "${TEST_KEY}_OTHER_APP" "List hides other apps' entries"

# A tagged credential wins even when a different account registered the name first.
shared="${TEST_KEY}_SHARED"
security add-generic-password -s "$shared" -a other -w original
security add-generic-password -s "$shared" -a "$USER" -c 'kcm ' -w tagged
assert_equals "tagged" "$("$SCRIPT_PATH" show "$shared")" "Show selects the tagged credential"
printf updated | "$SCRIPT_PATH" add "$shared" - >/dev/null 2>&1
assert_equals "updated" "$("$SCRIPT_PATH" show "$shared")" "Add updates the tagged credential"
"$SCRIPT_PATH" remove "$shared" >/dev/null 2>&1
assert_equals "original" "$("$SCRIPT_PATH" show "$shared")" "Remove leaves the other account intact"

# Two tagged items are equally good matches. Neither may be removed by name.
collision="${TEST_KEY}_COLLISION"
for acct in one two; do
    security add-generic-password -s "$collision" -a "$acct" -c 'kcm ' -w "$acct"
done
output=$("$SCRIPT_PATH" remove "$collision" 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Refuses to remove an ambiguous credential"
assert_contains "$output" "ambiguous" "Explains why the credential cannot be selected"
for acct in one two; do
    security delete-generic-password -s "$collision" -a "$acct" >/dev/null 2>&1 || true
done

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

# show | add keeps trailing newlines, so it can retag an entry without changing its value
printf 'abc\n\n' | "$SCRIPT_PATH" add "$TEST_KEY" - >/dev/null 2>&1
"$SCRIPT_PATH" show "$TEST_KEY" | "$SCRIPT_PATH" add "$TEST_KEY" - >/dev/null 2>&1
assert_equals "$(printf 'abc\n\nx')" "$("$SCRIPT_PATH" show "$TEST_KEY"; printf x)" "show piped to add keeps a trailing newline"

# Capture pbcopy's input without changing the user's clipboard.
mkdir -p "$TEST_DIR/pasteboard"
printf '#!/bin/sh\ncat > "$TEST_CLIPBOARD"\n' > "$TEST_DIR/pasteboard/pbcopy"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/pasteboard/pbpaste"
cp "$TEST_DIR/pasteboard/pbpaste" "$TEST_DIR/pasteboard/sleep"
chmod +x "$TEST_DIR/pasteboard/"*
TEST_CLIPBOARD="$TEST_DIR/copied" PATH="$TEST_DIR/pasteboard:$PATH" "$SCRIPT_PATH" copy "$TEST_KEY" >/dev/null 2>&1
assert_equals "$(printf 'abc\nx')" "$(cat "$TEST_DIR/copied"; printf x)" "Copy preserves the stored trailing newline"

# A value near the security -i line limit still stores whole
long=$(head -c 2020 /dev/zero | tr '\0' 'v')
printf '%s' "$long" | "$SCRIPT_PATH" add "${TEST_KEY}_LONG" - >/dev/null 2>&1
assert_equals "$long" "$("$SCRIPT_PATH" show "${TEST_KEY}_LONG" 2>&1)" "Stores a value near the security -i line limit"

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

# A file named "environment" is a file like any other, not the exported-variable marker
printf 'FROM_FILE=keychain://%s_QUOTE\n' "$TEST_KEY" > "$TEST_DIR/environment"
output=$(cd "$TEST_DIR" && "$SCRIPT_PATH" use -e environment -- printenv FROM_FILE 2>&1)
assert_equals "keychain_secret" "$output" "Resolves references from a file named environment"

# Test 13: Use command with env file
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$SIMPLE_VAR"' 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 0 "$exit_code" "Use command with env file"
assert_equals "simple_value" "$output" "Simple variable resolved"

# Test 14: Quoted values
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$DOUBLE_QUOTED"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "quoted value" "$output" "Double quoted value handled"

output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$SINGLE_QUOTED"' 2>&1) && exit_code=$? || exit_code=$?
assert_equals "single quoted" "$output" "Single quoted value handled"

# A closing quote on its own line keeps the line break before it, as dotenv does
printf 'TRAILING="line 1\n"\n' > "$TEST_DIR/trail.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/trail.env" -- bash -c 'printf "%sx" "$TRAILING"' 2>&1)
assert_equals "$(printf 'line 1\nx')" "$output" "Keeps the line break before a closing quote on its own line"

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

printf 'BEFORE=yes\nTOKEN="unfinished\nAFTER=no\n' > "$TEST_DIR/broken.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/broken.env" -- echo ran 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Unclosed quote stops the command"
assert_contains "$output" "$TEST_DIR/broken.env:2" "Unclosed quote reports its opening line"

# Test 22: Command with arguments
output=$("$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo $1 $2' -- "arg1" "arg2" 2>&1) && exit_code=$? || exit_code=$?
assert_equals "arg1 arg2" "$output" "Arguments passed correctly"

# Without --, kcm's options end at the command: its flags are not kcm's
output=$("$SCRIPT_PATH" use -e "$TEST_ENV" printf '[%s]' -s x -e y 2>/dev/null) && exit_code=$? || exit_code=$?
assert_equals "[-s][x][-e][y]" "$output" "Flags after the command go to the command"

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

# kcm's own variable names must not replace exported ones
output=$(VERSION=caller k=caller env_file=caller "$SCRIPT_PATH" use --env-file "$TEST_ENV" -- bash -c 'echo "$VERSION $k $env_file"' 2>/dev/null)
assert_equals "caller caller caller" "$output" "Exported names kcm uses internally pass through unchanged"
printf 'value=file\nname=file\n' > "$TEST_DIR/names.env"
output=$(value=caller name=caller "$SCRIPT_PATH" use --env-file "$TEST_DIR/names.env" --full 2>/dev/null | tr '\n' ' ')
assert_equals "name=caller value=caller " "$output" "Listing shows exported values for names kcm uses internally"
printf '_kcm_name=file\n' > "$TEST_DIR/reserved.env"
output=$(_kcm_name=caller "$SCRIPT_PATH" use --env-file "$TEST_DIR/reserved.env" --full 2>&1 | cat)
assert_contains "$output" "_kcm_name is reserved by kcm" "Listing refuses kcm's prefix even when exported"

output=$(FOO=shell-value-at-least-24-chars "$SCRIPT_PATH" use --env-file "$TEST_ENV" -s 2>/dev/null)
assert_equals "FOO=shel…hars" "$output" "Listing shows the environment value"
output=$(FOO=shell "$SCRIPT_PATH" use --env-file "$TEST_ENV" 2>/dev/null | tr -s ' ')
assert_equals "FOO environment" "$output" "Listing names the environment as source"

# No Keychain lookup for a variable the environment already sets
printf 'GONE=keychain://KCM_TEST_MISSING_%s\n' "$$" > "$TEST_ENV"
output=$(GONE=shell "$SCRIPT_PATH" use --env-file "$TEST_ENV" -- true 2>&1)
assert_not_contains "$output" "not found" "Skips Keychain lookup for variable set in environment"

# A shell value that hides a different env file value is named before the command runs
printf 'FOO=file\nSAME=same\nONLY_FILE=1\n' > "$TEST_ENV"
output=$(FOO=shell SAME=same "$SCRIPT_PATH" use --env-file "$TEST_ENV" -- true 2>&1)
assert_contains "$output" "Warning: set in your shell, so the env file value is not used: FOO (--override uses the file)" "Names the variable the shell overrides"
assert_not_contains "$output" "SAME" "No warning when the shell and the file agree"

# --override: the env file wins, references included
output=$(FOO=shell "$SCRIPT_PATH" use --override --env-file "$TEST_ENV" -- bash -c 'echo "$FOO"' 2>&1)
assert_equals "file" "$output" "--override uses the env file value and does not warn"
printf 'REF=keychain://%s_QUOTE\n' "$TEST_KEY" > "$TEST_DIR/override.env"
output=$(REF=shell "$SCRIPT_PATH" use --override -e "$TEST_DIR/override.env" -- printenv REF 2>/dev/null)
assert_equals "keychain_secret" "$output" "--override resolves a reference the shell also sets"

# A hidden reference is named too, unless an outer kcm use resolved that same reference
output=$(REF=shell "$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- true 2>&1)
assert_contains "$output" "is not used: REF (" "Names a reference the shell overrides"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- "$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- printenv REF 2>&1)
assert_equals "keychain_secret" "$output" "Nested use does not warn about what the outer one loaded"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- env REF=changed "$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- true 2>&1)
assert_contains "$output" "is not used: REF (" "Nested use warns when the value changed after the outer one loaded it"
printf 'REF=keychain://%s\n' "$TEST_KEY" > "$TEST_DIR/override-other.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- "$SCRIPT_PATH" use -e "$TEST_DIR/override-other.env" -- true 2>&1)
assert_contains "$output" "is not used: REF (" "Nested use warns when its file points at another entry"
# The shell holding the same reference unresolved still hides the Keychain value
output=$(REF="keychain://${TEST_KEY}_QUOTE" "$SCRIPT_PATH" use -e "$TEST_DIR/override.env" -- true 2>&1)
assert_contains "$output" "is not used: REF (" "Names a reference the shell holds unresolved"

# --override does not let an env file replace a variable that changes how Bash starts
printf 'echo HOOK_RAN\n' > "$TEST_DIR/hook.sh"
printf 'BASH_ENV=%s/hook.sh\n' "$TEST_DIR" > "$TEST_DIR/bash-env.env"
output=$(BASH_ENV=/dev/null "$SCRIPT_PATH" use --override -e "$TEST_DIR/bash-env.env" -- bash -c 'echo child' 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "--override rejects BASH_ENV even when the caller exports it"
assert_not_contains "$output" "HOOK_RAN" "--override does not run the env file's BASH_ENV script"
# Nor PS4, which a tracing Bash runs as code
printf "PS4='\$(touch %s/ps4-ran)'\n" "$TEST_DIR" > "$TEST_DIR/ps4.env"
PS4='+ ' "$SCRIPT_PATH" use --override -e "$TEST_DIR/ps4.env" -- bash -xc true >/dev/null 2>&1 && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "--override rejects PS4 even when the caller exports it"
assert_equals "no" "$([ -e "$TEST_DIR/ps4-ran" ] && echo yes || echo no)" "--override does not run the env file's PS4 command"

# Bash evaluates an assignment to an integer variable as arithmetic, which can run a command
printf "OPTIND='_KCM_MERGED_VALUES[\$(touch %s/optind-ran)0]'\n" "$TEST_DIR" > "$TEST_DIR/optind.env"
output=$(env -u OPTIND "$SCRIPT_PATH" use -e "$TEST_DIR/optind.env" -- true 2>&1) && exit_code=0 || exit_code=$?
assert_contains "$output" "OPTIND is managed by Bash" "Rejects OPTIND from an env file"
assert_equals "no" "$([ -e "$TEST_DIR/optind-ran" ] && echo yes || echo no)" "Does not evaluate an env file's OPTIND"
# The caller exporting such a variable does not make it an ordinary one for --override
printf "RANDOM='_KCM_MERGED_VALUES[\$(touch %s/random-ran)0]'\n" "$TEST_DIR" > "$TEST_DIR/random.env"
output=$(RANDOM=1 "$SCRIPT_PATH" use --override -e "$TEST_DIR/random.env" -- true 2>&1) && exit_code=0 || exit_code=$?
assert_contains "$output" "RANDOM is managed by Bash" "--override rejects RANDOM even when the caller exports it"
assert_equals "no" "$([ -e "$TEST_DIR/random-ran" ] && echo yes || echo no)" "--override does not evaluate an env file's RANDOM"

printf 'FIRST=keychain://%s_MISSING\nUID=1000\n' "$TEST_KEY" > "$TEST_DIR/managed.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/managed.env" -- echo ran 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Rejects a Bash-managed name"
assert_contains "$output" "$TEST_DIR/managed.env: UID is managed by Bash" "Names the file and reserved variable"
assert_not_contains "$output" "keychain://${TEST_KEY}_MISSING" "Checks names before resolving any secrets"

# Bash defines HOSTNAME without exporting it, but setting it is harmless and common.
printf 'HOSTNAME=0.0.0.0\n' > "$TEST_DIR/hostname.env"
output=$(env -u HOSTNAME "$SCRIPT_PATH" use -e "$TEST_DIR/hostname.env" -- sh -c 'echo "$HOSTNAME"' 2>&1)
assert_equals "0.0.0.0" "$output" "Passes HOSTNAME from a .env file"

printf 'CATALOGUE=keychain://%s_MISSING\n' "$TEST_KEY" > "$TEST_DIR/catalogue.env"
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/catalogue.env" 2>&1)
assert_contains "$output" "CATALOGUE" "Lists names from files with Keychain references"
assert_not_contains "$output" "not found in Keychain" "Listing names skips password lookups"

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

# In a terminal the = is dimmed; NO_COLOR and pipes (above) stay plain
output=$(NO_COLOR='' script -q /dev/null "$SCRIPT_PATH" use -e "$TEST_DIR/mask.env" --show-values 2>&1)
assert_contains "$output" $'LONG_SECRET\033[90m=' "Show values dims the = in a terminal"
assert_equals "LONG_SECRET=sk-a…9f2c" "$(strip_ansi <<< "$output" | grep -o 'LONG_SECRET=.*')" "Colour leaves the text unchanged"
output=$(NO_COLOR=1 script -q /dev/null "$SCRIPT_PATH" use -e "$TEST_DIR/mask.env" --show-values 2>&1)
assert_not_contains "$output" $'\033[90m=' "NO_COLOR keeps show values plain"

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

# Stays inside the git root
output=$(cd "$WRAP" && "$SCRIPT_PATH" install-wrapper ../outside/with-env 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Rejects a location outside the git root"
[ ! -e "$TEST_DIR/outside/with-env" ] && pass "Writes nothing outside the git root" || fail "Writes nothing outside the git root"
echo
echo "Test Group: Import"
echo "------------------"
IMP="$TEST_DIR/import"
mkdir -p "$IMP"

# A likely secret is pre-ticked: Enter accepts the list, y confirms
cat > "$IMP/.env" << EOF
# config
${TEST_KEY}_API_KEY=sk-test-123
PORT=3000
EOF
(cd "$IMP" && printf '\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "sk-test-123" "$("$SCRIPT_PATH" show "${TEST_KEY}_API_KEY" 2>&1)" "Import stores a detected secret"
assert_equals "$(printf '# config\n%s="keychain://%s"\nPORT=3000' "${TEST_KEY}_API_KEY" "${TEST_KEY}_API_KEY")" "$(cat "$IMP/.env")" "Import replaces only the imported line"
attrs=$(security find-generic-password -s "${TEST_KEY}_API_KEY" 2>&1)
assert_contains "$attrs" "\"icmt\"<blob>=\"Imported by kcm from $(cd "$IMP" && pwd -P)/.env\"" "Imported secret's comment names its source file"
assert_contains "$attrs" '"desc"<blob>="kcm secret"' "Imported secret has kind 'kcm secret'"

# security prints a comment with non-ASCII text as hex; ls must still hide kcm's own
ACC="$TEST_DIR/café"
mkdir -p "$ACC"
echo "${TEST_KEY}_ACCENT=sk-test-789" > "$ACC/.env"
(cd "$ACC" && printf '\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "sk-test-789" "$("$SCRIPT_PATH" show "${TEST_KEY}_ACCENT" 2>&1)" "Import works from a folder with an accented name"
assert_not_contains "$("$SCRIPT_PATH" ls "${TEST_KEY}_ACCENT" 2>&1)" "Imported by kcm" "ls hides kcm's import comment when the path has accented letters"

# A newline in the source path must not start a second security -i command
INJ="$TEST_DIR/inj"$'\n'"add-generic-password -s ${TEST_KEY}_INJECTED -a x -w y"$'\n'"z"
mkdir -p "$INJ"
"$SCRIPT_PATH" remove "${TEST_KEY}_API_KEY" >/dev/null 2>&1
echo "${TEST_KEY}_API_KEY=sk-test-456" > "$INJ/.env"
(cd "$INJ" && printf '\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "sk-test-456" "$("$SCRIPT_PATH" show "${TEST_KEY}_API_KEY" 2>&1)" "Import stores from a path with a newline"
security find-generic-password -s "${TEST_KEY}_INJECTED" >/dev/null 2>&1 \
  && fail "Newline in path runs no extra security command" || pass "Newline in path runs no extra security command"

# A multiline quoted value is stored whole and its extra lines are removed
cat > "$IMP/.env" << EOF
export ${TEST_KEY}_MULTI="-----BEGIN KEY-----
abc
-----END KEY-----" # pem
AFTER=1
EOF
(cd "$IMP" && printf '\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "$(printf -- '-----BEGIN KEY-----\nabc\n-----END KEY-----')" "$("$SCRIPT_PATH" show "${TEST_KEY}_MULTI" 2>&1)" "Import stores a multiline value whole"
assert_equals "$(printf 'export %s="keychain://%s"\nAFTER=1' "${TEST_KEY}_MULTI" "${TEST_KEY}_MULTI")" "$(cat "$IMP/.env")" "Import collapses a multiline value to one reference line"

# A name already in Keychain with another value: keep it, or rename the new one
echo "old-value" | "$SCRIPT_PATH" add "${TEST_KEY}_CLASH" - >/dev/null 2>&1
echo "${TEST_KEY}_CLASH=new-value" > "$IMP/.env"
(cd "$IMP" && printf '\nk\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "old-value" "$("$SCRIPT_PATH" show "${TEST_KEY}_CLASH" 2>&1)" "Import keep leaves the Keychain value"
assert_equals "${TEST_KEY}_CLASH=\"keychain://${TEST_KEY}_CLASH\"" "$(cat "$IMP/.env")" "Import keep references the existing entry"

echo "${TEST_KEY}_CLASH=new-value" > "$IMP/.env"
(cd "$IMP" && printf '\nr\n%s\ny\n' "${TEST_KEY}_RENAMED" | "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "new-value" "$("$SCRIPT_PATH" show "${TEST_KEY}_RENAMED" 2>&1)" "Import rename stores under the new name"
assert_equals "${TEST_KEY}_CLASH=\"keychain://${TEST_KEY}_RENAMED\"" "$(cat "$IMP/.env")" "Import rename references the new name"

# Quitting at the confirmation changes nothing; the list ticks likely secrets and masks values
"$SCRIPT_PATH" remove "${TEST_KEY}_API_KEY" >/dev/null 2>&1
cat > "$IMP/.env" << EOF
${TEST_KEY}_API_KEY=sk-live-abcdefghijklmnopqrstuvwxyz
DB=postgres://user:pw@localhost/db
NEXT_PUBLIC_MAP_KEY=pk-public
PORT=3000
EOF
before=$(cat "$IMP/.env")
output=$(cd "$IMP" && printf '\n' | "$SCRIPT_PATH" import 2>&1) && exit_code=$? || exit_code=$?
assert_exit_code 1 "$exit_code" "Import cancelled at the confirmation exits 1"
assert_equals "$before" "$(cat "$IMP/.env")" "Import cancelled leaves the file unchanged"
"$SCRIPT_PATH" show "${TEST_KEY}_API_KEY" >/dev/null 2>&1 && fail "Import cancelled stores nothing" || pass "Import cancelled stores nothing"
assert_not_contains "$output" "abcdefghijklmnop" "Import list masks values"
assert_contains "$output" "[x]  1  ${TEST_KEY}_API_KEY" "Import ticks a secret by name"
assert_contains "$output" "[x]  2  DB" "Import ticks a URL with a password"
assert_contains "$output" "[ ]  3  NEXT_PUBLIC_MAP_KEY" "Import leaves public-prefixed names unticked"
assert_contains "$output" "[ ]  4  PORT" "Import leaves plain settings unticked"
assert_contains "$(grep "${TEST_KEY}_API_KEY" <<< "$output")" "name has KEY, starts with sk-" "Import notes say which word and prefix matched"
assert_contains "$(grep ' DB ' <<< "$output")" "URL with password" "Import notes a URL with a password"
assert_contains "$(grep NEXT_PUBLIC_MAP_KEY <<< "$output")" "name has KEY · public, so unticked" "Import notes why a public name is unticked"

# The same name in two files: the closer, higher-priority file gets the plain name.
# A git-tracked file is listed but not ticked.
IG="$TEST_DIR/import-git"
mkdir -p "$IG"
git -C "$IG" init -q
echo "${TEST_KEY}_API_KEY=shared-value" > "$IG/.env"
git -C "$IG" add .env
echo "${TEST_KEY}_API_KEY=local-value" > "$IG/.env.local"
"$SCRIPT_PATH" remove "${TEST_KEY}_API_KEY" >/dev/null 2>&1
"$SCRIPT_PATH" remove "${TEST_KEY}_RENAMED" >/dev/null 2>&1
output=$(cd "$IG" && printf '2\n\nr\n%s\ny\n' "${TEST_KEY}_RENAMED" | "$SCRIPT_PATH" import 2>&1)
assert_contains "$output" "[ ]  2  ${TEST_KEY}_API_KEY  ./.env" "Import leaves a git-tracked file unticked"
assert_equals "local-value" "$("$SCRIPT_PATH" show "${TEST_KEY}_API_KEY" 2>&1)" "Import gives the plain name to .env.local"
assert_equals "shared-value" "$("$SCRIPT_PATH" show "${TEST_KEY}_RENAMED" 2>&1)" "Import stores the clashing .env value under the new name"
assert_equals "${TEST_KEY}_API_KEY=\"keychain://${TEST_KEY}_RENAMED\"" "$(cat "$IG/.env")" "Import points .env at the renamed entry"

# A symlinked env file keeps its target's permissions when rewritten
printf '%s_LINK_KEY=sk-link-1\n' "$TEST_KEY" > "$IMP/real.env"
chmod 600 "$IMP/real.env"
ln -s real.env "$IMP/link.env"
(cd "$IMP" && printf '\ny\n' | "$SCRIPT_PATH" import -e link.env >/dev/null 2>&1)
assert_equals "600" "$(/usr/bin/stat -f %Lp "$IMP/link.env")" "Import keeps a symlinked file's permissions"

# A value ending in a newline still reads back, so its line is replaced
printf '%s_NL_KEY="abc\n\n"\n' "$TEST_KEY" > "$IMP/nl.env"
(cd "$IMP" && printf '\ny\n' | "$SCRIPT_PATH" import -e nl.env >/dev/null 2>&1)
assert_equals "${TEST_KEY}_NL_KEY=\"keychain://${TEST_KEY}_NL_KEY\"" "$(cat "$IMP/nl.env")" "Import replaces a value with a trailing newline"
output=$("$SCRIPT_PATH" use -e "$IMP/nl.env" -- bash -c "printf '%sx' \"\$${TEST_KEY}_NL_KEY\"" 2>&1)
assert_equals "$(printf 'abc\n\nx')" "$output" "use resolves an imported value with its trailing newlines"

# A public name stays unticked even when Keychain has the same value
echo "pk-same" | "$SCRIPT_PATH" add "NEXT_PUBLIC_${TEST_KEY}_KEY" - >/dev/null 2>&1
printf 'NEXT_PUBLIC_%s_KEY=pk-same\n' "$TEST_KEY" > "$IMP/pub.env"
output=$(cd "$IMP" && printf '\n' | "$SCRIPT_PATH" import -e pub.env 2>&1)
assert_contains "$output" "[ ]  1  NEXT_PUBLIC_${TEST_KEY}_KEY" "Import leaves a public name unticked when Keychain has its value"

# A file edited while kcm asks is left alone
printf '%s_MOVED_KEY=sk-moved-1\n' "$TEST_KEY" > "$IMP/moved.env"
(cd "$IMP" && { printf '\n'; sleep 2; printf 'PORT=3000\n%s_MOVED_KEY=sk-moved-1\n' "$TEST_KEY" > moved.env; printf 'y\n'; } \
  | "$SCRIPT_PATH" import -e moved.env >/dev/null 2>&1) && exit_code=$? || exit_code=$?
assert_equals "$(printf 'PORT=3000\n%s_MOVED_KEY=sk-moved-1' "$TEST_KEY")" "$(cat "$IMP/moved.env")" "Import leaves a file changed during the prompts alone"
assert_exit_code 1 "$exit_code" "Import exits 1 when a file changed during the prompts"

# A file edited while kcm stores values is left alone: a security wrapper edits it mid-store
MID="$TEST_DIR/mid"
mkdir -p "$MID/bin"
cat > "$MID/bin/security" << 'EOF'
#!/bin/bash
if [ "${1:-}" = -i ]; then
  { printf 'PORT=3000\n'; cat "$MID_FILE"; } > "$MID_FILE.new" && mv "$MID_FILE.new" "$MID_FILE"
fi
exec "$TEST_SECURITY" "$@"
EOF
chmod +x "$MID/bin/security"
printf '%s_MID_KEY=sk-mid-1\n' "$TEST_KEY" > "$MID/.env"
(cd "$MID" && printf '\ny\n' | MID_FILE="$MID/.env" TEST_SECURITY="$(command -v security)" PATH="$MID/bin:$PATH" "$SCRIPT_PATH" import >/dev/null 2>&1) && exit_code=$? || exit_code=$?
assert_equals "$(printf 'PORT=3000\n%s_MID_KEY=sk-mid-1' "$TEST_KEY")" "$(cat "$MID/.env")" "Import leaves a file changed during the store alone"
assert_exit_code 1 "$exit_code" "Import exits 1 when a file changed during the store"

# A kept Keychain value that changes during the prompts is not referenced
echo "sk-ref-1" | "$SCRIPT_PATH" add "${TEST_KEY}_REF_KEY" - >/dev/null 2>&1
printf '%s_REF_KEY=sk-ref-1\n' "$TEST_KEY" > "$IMP/ref.env"
(cd "$IMP" && { printf '\n'; sleep 2; echo "sk-ref-2" | "$SCRIPT_PATH" add "${TEST_KEY}_REF_KEY" - >/dev/null 2>&1; printf 'y\n'; } \
  | "$SCRIPT_PATH" import -e ref.env >/dev/null 2>&1) && exit_code=$? || exit_code=$?
assert_equals "${TEST_KEY}_REF_KEY=sk-ref-1" "$(cat "$IMP/ref.env")" "Import keeps the plain value when the Keychain value changed"
assert_exit_code 1 "$exit_code" "Import exits 1 when a kept Keychain value changed"

# Two picked values overwriting one label: only the file whose value won gets the reference
DUP="$TEST_DIR/dup"
mkdir -p "$DUP"
printf '%s_DUP_KEY=sk-dup-a\n' "$TEST_KEY" > "$DUP/.env"
printf '%s_DUP_KEY=sk-dup-b\n' "$TEST_KEY" > "$DUP/.env.local"
(cd "$DUP" && printf '\no\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1) && exit_code=$? || exit_code=$?
kept=$("$SCRIPT_PATH" show "${TEST_KEY}_DUP_KEY" 2>&1)
plain=$(cat "$DUP/.env" "$DUP/.env.local" | grep -c '=sk-dup-' || true)
assert_equals "1" "$plain" "Import keeps the overwritten value in its file"
assert_not_contains "$(cat "$DUP/.env" "$DUP/.env.local")" "=$kept" "Import leaves no plain copy of the stored value"
assert_exit_code 1 "$exit_code" "Import exits 1 when a picked value was overwritten"

# A file kcm can't rewrite makes import fail
RO="$TEST_DIR/readonly"
mkdir -p "$RO"
printf '%s_RO_KEY=sk-ro-1\n' "$TEST_KEY" > "$RO/.env"
chmod 555 "$RO"
(cd "$RO" && printf '\ny\n' | "$SCRIPT_PATH" import >/dev/null 2>&1) && exit_code=$? || exit_code=$?
chmod 755 "$RO"
assert_exit_code 1 "$exit_code" "Import exits 1 when a file can't be rewritten"

# In a terminal: space toggles, the down arrow moves, Enter accepts.
# script runs kcm on a pseudo-terminal so it uses the key-driven list.
"$SCRIPT_PATH" remove "${TEST_KEY}_API_KEY" >/dev/null 2>&1
"$SCRIPT_PATH" remove "${TEST_KEY}_CLASH" >/dev/null 2>&1
printf '%s\n' "${TEST_KEY}_API_KEY=first" "${TEST_KEY}_CLASH=second" > "$IMP/.env"
(cd "$IMP" && printf ' \033[B\ny\n' | script -q /dev/null "$SCRIPT_PATH" import >/dev/null 2>&1)
assert_equals "$(printf '%s=first\n%s="keychain://%s"' "${TEST_KEY}_API_KEY" "${TEST_KEY}_CLASH" "${TEST_KEY}_CLASH")" "$(cat "$IMP/.env")" "Import picks with arrow keys and space in a terminal"

# The list marks names already in Keychain and shows existing references
echo "same" | "$SCRIPT_PATH" add "${TEST_KEY}_API_KEY" - >/dev/null 2>&1
echo "old" | "$SCRIPT_PATH" add "${TEST_KEY}_CLASH" - >/dev/null 2>&1
cat > "$IMP/.env" << EOF
${TEST_KEY}_API_KEY=same
${TEST_KEY}_CLASH=new
DONE_REF=keychain://${TEST_KEY}_API_KEY
BROKEN_REF=keychain://${TEST_KEY}_MISSING
EOF
output=$(cd "$IMP" && printf '\n' | "$SCRIPT_PATH" import 2>&1 | strip_ansi)
assert_contains "$output" "${TEST_KEY}_API_KEY  ./.env  ****       name has KEY · in Keychain, same value" "Import marks a name in Keychain with the same value"
assert_contains "$output" "${TEST_KEY}_CLASH    ./.env  ****       name has KEY · in Keychain, different value" "Import marks a name in Keychain with another value"
assert_contains "$(grep DONE_REF <<< "$output")" "✓" "Import shows an existing reference as done"
assert_contains "$(grep BROKEN_REF <<< "$output")" "missing from Keychain" "Import flags a reference missing from Keychain"

printf 'BROKEN=keychain://%s_MISSING\n' "$TEST_KEY" > "$TEST_DIR/refs.env"
output=$("$SCRIPT_PATH" import -e "$TEST_DIR/refs.env" </dev/null 2>&1)
assert_contains "$output" "keychain://${TEST_KEY}_MISSING missing from Keychain" "Reports a broken reference in a fully imported file"

# In the key-driven list, the NAME heading starts in the same column as the names
printf 'LONG_NAME_FOR_ALIGN=plain\n' > "$IMP/.env"
output=$(cd "$IMP" && printf 'q' | script -q /dev/null "$SCRIPT_PATH" import 2>&1 | strip_ansi)
header=$(grep -m1 'NAME' <<< "$output"); row=$(grep -m1 'LONG_NAME_FOR_ALIGN' <<< "$output")
[ -n "$header" ] && [ -n "$row" ] && pass "Import list draws the heading and row" || fail "Import list draws the heading and row"
header="${header%%NAME*}"; row="${row%%LONG_NAME_FOR_ALIGN*}"
assert_equals "${#header}" "${#row}" "Import list headings line up with the columns"

echo
echo "Test Group: Pattern Matching"
echo "----------------------------"

# Add test secrets for pattern matching
echo
echo "Test Group: Export"
echo "------------------"

# A reference, a multiline value, a value with ' and a literal \n that dotenv would expand in "..."
printf 'exported-secret' | "$SCRIPT_PATH" add "${TEST_KEY}_EXPORT" - >/dev/null 2>&1
cat > "$TEST_DIR/export.env" <<EOF
REF=keychain://${TEST_KEY}_EXPORT
PEM="-----BEGIN-----
abc
-----END-----"
QUOTE="it's here"
SLASH='back\n slash'
EOF
expected=$("$SCRIPT_PATH" use -e "$TEST_DIR/export.env" --full 2>/dev/null | cat)
"$SCRIPT_PATH" export -e "$TEST_DIR/export.env" -o "$TEST_DIR/exported.env" 2>/dev/null
output=$("$SCRIPT_PATH" use -e "$TEST_DIR/exported.env" --full 2>/dev/null | cat)
assert_contains "$expected" "REF=exported-secret" "Export test resolves the reference"
assert_equals "$expected" "$output" "Exported file reads back to the same values"
assert_equals "600" "$(stat -f %Lp "$TEST_DIR/exported.env")" "Exported file is readable only by its owner"

before=$(cat "$TEST_DIR/exported.env")
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export.env" -o "$TEST_DIR/exported.env" 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Export refuses an existing file"
assert_equals "$before" "$(cat "$TEST_DIR/exported.env")" "Existing file is left unchanged"

printf 'OK=1\nGONE=keychain://%s_MISSING\n' "$TEST_KEY" > "$TEST_DIR/export-missing.env"
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export-missing.env" -o "$TEST_DIR/missing-out.env" 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Export fails on a missing Keychain entry"
assert_contains "$output" "GONE" "Names the variable with the missing entry"
[ -e "$TEST_DIR/missing-out.env" ] && fail "Writes no file when an entry is missing" || pass "Writes no file when an entry is missing"

printf "BOTH=a'b\"c\n" > "$TEST_DIR/export-both.env"
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export-both.env" 2>&1 | cat) && exit_code=0 || exit_code=$?
assert_contains "$output" "Cannot quote BOTH" "Export fails on a value it can't quote"

# dotenv turns any carriage return into a newline, so the value would not read back
printf 'CR=a\rb\n' > "$TEST_DIR/export-cr.env"
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export-cr.env" 2>&1 | cat)
assert_contains "$output" "Cannot quote CR" "Export fails on a value with a carriage return"

# Exported names that match kcm's own variable names keep their values
printf 'name=file\nvalue=file\nk=file\nenv_file=file\ntext=file\ncount=file\n' > "$TEST_DIR/export-names.env"
output=$(name=caller value=caller k=caller env_file=caller text=caller count=caller \
    "$SCRIPT_PATH" export -e "$TEST_DIR/export-names.env" 2>/dev/null | tr '\n' ' ')
assert_equals "name='caller' value='caller' k='caller' env_file='caller' text='caller' count='caller' " "$output" "Export keeps exported values for names kcm uses internally"

# Export warns when it writes a shell value in place of the file's, and --override writes the file's
printf 'FOO=file\nREF=keychain://%s_QUOTE\n' "$TEST_KEY" > "$TEST_DIR/export-override.env"
output=$(FOO=shell REF=shell "$SCRIPT_PATH" export -e "$TEST_DIR/export-override.env" 2>/dev/null | tr '\n' ' ')
assert_equals "FOO='shell' REF='shell' " "$output" "Export still writes the shell values by default"
output=$(FOO=shell REF=shell "$SCRIPT_PATH" export -e "$TEST_DIR/export-override.env" 2>&1 >/dev/null)
assert_contains "$output" "is not used: FOO, REF (--override uses the file)" "Export names the variables the shell overrides"
output=$(FOO=shell REF=shell "$SCRIPT_PATH" export --override -e "$TEST_DIR/export-override.env" 2>&1 | tr '\n' ' ')
assert_equals "FOO='file' REF='keychain_secret' " "$output" "Export --override writes the env file values and does not warn"

# kcm's own prefix is reserved, even when the caller exports it
printf '_kcm_name=file\n' > "$TEST_DIR/export-reserved.env"
output=$(_kcm_name=caller "$SCRIPT_PATH" export -e "$TEST_DIR/export-reserved.env" 2>&1 | cat)
assert_contains "$output" "_kcm_name is reserved by kcm" "Export refuses a name with kcm's prefix"
assert_not_contains "$output" "_kcm_name=" "Reserved name prints no value"

# Another user could swap the temp file in a folder they can write to, unless it is sticky
mkdir -p "$TEST_DIR/shared" "$TEST_DIR/sticky"
chmod 777 "$TEST_DIR/shared"; chmod 1777 "$TEST_DIR/sticky"
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export.env" -o "$TEST_DIR/shared/out.env" 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Export refuses a folder others can write to"
[ -e "$TEST_DIR/shared/out.env" ] && fail "Writes nothing to a folder others can write to" || pass "Writes nothing to a folder others can write to"
"$SCRIPT_PATH" export -e "$TEST_DIR/export.env" -o "$TEST_DIR/sticky/out.env" >/dev/null 2>&1 && exit_code=0 || exit_code=$?
assert_exit_code 0 "$exit_code" "Export writes to a sticky folder"
ln -s shared "$TEST_DIR/shared-link"
output=$("$SCRIPT_PATH" export -e "$TEST_DIR/export.env" -o "$TEST_DIR/shared-link/out.env" 2>&1) && exit_code=0 || exit_code=$?
assert_exit_code 1 "$exit_code" "Export checks the folder a symlink points to"

# In a terminal the text goes to less; this stand-in records what it was given
mkdir -p "$TEST_DIR/bin"
printf '#!/bin/sh\ncat > "%s/paged.txt"\n' "$TEST_DIR" > "$TEST_DIR/bin/less"
chmod +x "$TEST_DIR/bin/less"
output=$(PATH="$TEST_DIR/bin:$PATH" script -q /dev/null "$SCRIPT_PATH" export -e "$TEST_DIR/export.env" 2>&1)
assert_not_contains "$output" "exported-secret" "Export in a terminal prints no values directly"
assert_equals "$(cat "$TEST_DIR/exported.env")" "$(cat "$TEST_DIR/paged.txt" 2>/dev/null)" "Export in a terminal opens the quoted text in less"

echo "value1" | "$SCRIPT_PATH" add "${TEST_KEY}_TEST_PATTERN_ONE" - >/dev/null 2>&1
echo "value2" | "$SCRIPT_PATH" add "${TEST_KEY}_TEST_PATTERN_TWO" - >/dev/null 2>&1
echo "value3" | "$SCRIPT_PATH" add "${TEST_KEY}_OTHER_PATTERN" - >/dev/null 2>&1

# Test 23: List with pattern
output=$("$SCRIPT_PATH" ls "${TEST_KEY}_TEST_PATTERN*" 2>&1) && exit_code=$? || exit_code=$?
assert_contains "$output" "${TEST_KEY}_TEST_PATTERN_ONE" "Pattern matches first key"
assert_contains "$output" "${TEST_KEY}_TEST_PATTERN_TWO" "Pattern matches second key"
assert_not_contains "$output" "${TEST_KEY}_OTHER_PATTERN" "Pattern excludes non-matching"

# Cleanup pattern test keys
"$SCRIPT_PATH" remove "${TEST_KEY}_TEST_PATTERN_ONE" >/dev/null 2>&1
"$SCRIPT_PATH" remove "${TEST_KEY}_TEST_PATTERN_TWO" >/dev/null 2>&1
"$SCRIPT_PATH" remove "${TEST_KEY}_OTHER_PATTERN" >/dev/null 2>&1

echo
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi