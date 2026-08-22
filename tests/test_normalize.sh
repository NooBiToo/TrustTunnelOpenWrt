#!/bin/sh
. "$(dirname "$0")/lib.sh"

NORM=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/normalize

run() { printf '%s\n' "$1" | sh "$NORM" 2>/dev/null; }
run_err() { printf '%s\n' "$1" | sh "$NORM" 2>&1 >/dev/null; }

assert_eq "example.com" "$(run 'EXAMPLE.COM')" "lowercases"
assert_eq "ua" "$(run '.ua')" "strips leading dot"
assert_eq "example.com" "$(run '*.example.com')" "strips leading wildcard"
assert_eq "example.com" "$(run 'example.com.')" "strips trailing dot"
assert_eq "example.com" "$(run '   example.com   ')" "trims whitespace"
assert_eq "" "$(run '# comment')" "drops full-line comments"
assert_eq "example.com" "$(run 'example.com # why')" "drops trailing comments"
assert_eq "" "$(run '')" "drops empty lines"

assert_eq "a.com
b.com" "$(printf 'a.com\nb.com\na.com\n' | sh "$NORM" 2>/dev/null)" "deduplicates, keeps order"

assert_eq "" "$(run 'two words.com')" "rejects embedded spaces"
assert_eq "" "$(run '1.2.3.4')" "rejects bare IPv4"
assert_eq "" "$(run 'bad_domain.com')" "rejects underscore"
assert_eq "" "$(run '-bad.com')" "rejects leading hyphen"
assert_eq "" "$(run 'bad-.com')" "rejects trailing hyphen"
assert_eq "" "$(run 'пример.рф')" "rejects non-ascii"
assert_eq "xn--80aswg.xn--p1ai" "$(run 'xn--80aswg.xn--p1ai')" "accepts punycode"
assert_eq "example.com" "$(printf 'example.com\r\n' | sh "$NORM" 2>/dev/null)" "accepts CRLF-terminated entry"

assert_eq "dropped 2" "$(printf 'ok.com\n1.2.3.4\nbad_x.com\n' | sh "$NORM" 2>&1 >/dev/null)" "reports drop count"
assert_eq "" "$(run_err 'ok.com')" "silent when nothing dropped"

tt_test_summary
