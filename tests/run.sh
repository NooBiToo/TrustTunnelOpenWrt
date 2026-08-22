#!/bin/sh
# Запускает все тест-файлы, каждый в своём временном каталоге.
set -u
cd "$(dirname "$0")/.." || exit 1

rc=0
for t in tests/test_*.sh; do
	echo "== $t"
	TT_TEST_TMP="$(mktemp -d)"
	export TT_TEST_TMP
	# stdin закрывается для каждого теста: ничто не должно читать его.
	# Заглушка или команда, случайно ждущая ввода, должна упасть сразу,
	# а не подвесить весь набор.
	if ! sh "$t" < /dev/null; then
		rc=1
	fi
	rm -rf "$TT_TEST_TMP"
done

if [ "$rc" = "0" ]; then
	echo "== all tests passed"
else
	echo "== FAILURES"
fi
exit "$rc"
