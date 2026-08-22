#!/bin/sh
. "$(dirname "$0")/lib.sh"

. packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/records.sh

TT_RECORDS=tests/fixtures/records/minimal.tsv

assert_eq "selective" "$(tt_get main.mode)" "tt_get reads a scalar"
assert_eq "" "$(tt_get main.nosuch)" "tt_get returns empty for missing key"
assert_eq "fallback" "$(tt_get main.nosuch fallback)" "tt_get honours default"
assert_eq "true" "$(tt_bool main.enabled)" "tt_bool maps 1 to true"
assert_eq "false" "$(tt_bool main.nosuch)" "tt_bool defaults to false"
assert_eq "true" "$(tt_bool main.nosuch 1)" "tt_bool honours default"
assert_eq "1" "$(tt_count endpoint.address)" "tt_count counts single value"

TT_RECORDS=tests/fixtures/records/full.tsv

assert_eq "1.2.3.4:443
[2001:db8::1]:443" "$(tt_list endpoint.address)" "tt_list returns all values"
assert_eq "2" "$(tt_count endpoint.address)" "tt_count counts list values"
assert_eq "0" "$(tt_count lists.nosuch)" "tt_count returns 0 for missing key"
assert_eq 'pa"ss\with' "$(tt_get endpoint.password)" "value stops at the first tab"
assert_eq "false" "$(tt_bool endpoint.post_quantum 1)" "explicit 0 beats default"

tt_test_summary
