#!/bin/sh
# Проверяем сам харнесс: ассерты должны и проходить, и падать когда надо.
. "$(dirname "$0")/lib.sh"

assert_eq "abc" "abc" "assert_eq accepts equal strings"
assert_contains "hello world" "lo wo" "assert_contains finds substring"
assert_exit 0 "assert_exit accepts success" true
assert_exit 1 "assert_exit accepts failure" false

# Негативная проверка: ассерт обязан зафиксировать провал.
( assert_eq "a" "b" "intentional failure" ) >/dev/null 2>&1
if [ "$(cat "$TT_TEST_TMP/failed")" = "1" ]; then
	echo "  ok: assert_eq records failures"
	echo 0 > "$TT_TEST_TMP/failed"
else
	echo "  FAIL: assert_eq did not record a failure"
	exit 1
fi

tt_test_summary
