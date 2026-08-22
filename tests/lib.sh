# Ассерты для тестов. Подключается через `. "$(dirname "$0")/lib.sh"`.
# POSIX sh: счётчики держим в файлах, чтобы они переживали подоболочки.

TT_TEST_TMP="${TT_TEST_TMP:-$(mktemp -d)}"
export TT_TEST_TMP
[ -f "$TT_TEST_TMP/total" ] || echo 0 > "$TT_TEST_TMP/total"
[ -f "$TT_TEST_TMP/failed" ] || echo 0 > "$TT_TEST_TMP/failed"

_tt_bump() {
	_f="$TT_TEST_TMP/$1"
	echo $(( $(cat "$_f") + 1 )) > "$_f"
}

_tt_pass() { _tt_bump total; echo "  ok: $1"; }
_tt_fail() { _tt_bump total; _tt_bump failed; echo "  FAIL: $1"; }

assert_eq() {
	_tt_expected="$1"; _tt_actual="$2"; _tt_msg="$3"
	if [ "$_tt_expected" = "$_tt_actual" ]; then
		_tt_pass "$_tt_msg"
	else
		_tt_fail "$_tt_msg"
		printf '    expected: %s\n    actual:   %s\n' "$_tt_expected" "$_tt_actual"
	fi
}

assert_contains() {
	case "$1" in
		*"$2"*) _tt_pass "$3" ;;
		*)
			_tt_fail "$3"
			printf '    missing: %s\n    in:      %s\n' "$2" "$1"
			;;
	esac
}

assert_exit() {
	_tt_want="$1"; _tt_msg="$2"; shift 2
	"$@" >/dev/null 2>&1
	_tt_got=$?
	if [ "$_tt_got" = "$_tt_want" ]; then
		_tt_pass "$_tt_msg"
	else
		_tt_fail "$_tt_msg"
		printf '    expected exit %s, got %s\n' "$_tt_want" "$_tt_got"
	fi
}

tt_test_summary() {
	_tt_t=$(cat "$TT_TEST_TMP/total")
	_tt_f=$(cat "$TT_TEST_TMP/failed")
	printf '  %s assertions, %s failed\n' "$_tt_t" "$_tt_f"
	[ "$_tt_f" = "0" ]
}
