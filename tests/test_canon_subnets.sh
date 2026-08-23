#!/bin/sh
. "$(dirname "$0")/lib.sh"

CANON=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/canon-subnets

run() { printf '%s' "$1" | sh "$CANON" 2>/dev/null; }

# Регистровый дубль схлопывается ТОЛЬКО когда в наборе есть оба варианта.
# Именно так он и попадает в конфигурацию: репозиторий списков держит
# Subnets/IPv4/Meta.lst и Subnets/IPv4/meta.lst байт в байт одинаковыми (то же
# с Twitter и Discord), интерфейс показывал обе строки, и человек отмечал обе.
assert_eq "Subnets/IPv4/meta.lst" \
	"$(run 'Subnets/IPv4/Meta.lst
Subnets/IPv4/meta.lst
')" "collapses a case duplicate to the lowercase variant"

assert_eq "Subnets/IPv4/meta.lst" \
	"$(run 'Subnets/IPv4/meta.lst
Subnets/IPv4/Meta.lst
')" "collapses regardless of which variant comes first"

# Одинокий вариант с заглавной буквы НЕ переписывается. Понижать регистр
# всегда нельзя: в наборе тогда оказался бы путь, которого в репозитории может
# не существовать, и fetch-lists печатал бы по нему `fail` при каждом
# обновлении списков. Присутствие обоих вариантов — само по себе
# доказательство, что оба файла существуют.
assert_eq "Subnets/IPv4/Meta.lst" \
	"$(run 'Subnets/IPv4/Meta.lst
')" "leaves a lone capitalised path alone"

# Разные семейства — разные файлы, схлопывать их нечем.
assert_eq "Subnets/IPv4/meta.lst
Subnets/IPv6/meta.lst" \
	"$(run 'Subnets/IPv4/meta.lst
Subnets/IPv6/meta.lst
')" "keeps both address families"

assert_eq "Subnets/IPv4/meta.lst
Subnets/IPv6/meta.lst" \
	"$(run 'Subnets/IPv4/Meta.lst
Subnets/IPv4/meta.lst
Subnets/IPv6/Meta.lst
Subnets/IPv6/meta.lst
')" "collapses each family on its own"

# Точный повтор — тоже повтор.
assert_eq "Subnets/IPv4/telegram.lst" \
	"$(run 'Subnets/IPv4/telegram.lst
Subnets/IPv4/telegram.lst
')" "drops exact duplicates"

# Порядок сохраняется: это выбор человека, и переставлять его незачем.
assert_eq "Subnets/IPv6/twitter.lst
Subnets/IPv4/meta.lst
Subnets/IPv4/telegram.lst" \
	"$(run 'Subnets/IPv6/twitter.lst
Subnets/IPv4/Meta.lst
Subnets/IPv4/meta.lst
Subnets/IPv4/telegram.lst
')" "keeps the original order of first appearance"

assert_eq "" "$(run '')" "empty input gives empty output"
assert_eq "" "$(run '

')" "blank lines are not entries"

assert_eq "Subnets/IPv4/meta.lst" \
	"$(run '  Subnets/IPv4/meta.lst
')" "trims surrounding whitespace"

# Файл без завершающего перевода строки — тот же случай, что уронил сборку
# списков: последняя запись обязана дойти целиком.
assert_eq "Subnets/IPv4/meta.lst" \
	"$(printf 'Subnets/IPv4/meta.lst' | sh "$CANON" 2>/dev/null)" \
	"reads the last entry without a trailing newline"

# Пути вне Subnets скрипт не трогает: он вызывается на одном списке
# lists.subnet, но фильтровать по префиксу значило бы молча терять запись,
# если репозиторий однажды разложит подсети иначе.
assert_eq "Categories/anime.lst" \
	"$(run 'Categories/anime.lst
')" "passes through paths outside Subnets"

# Регистр КАТАЛОГА не считается частью имени файла: Subnets/ipv4 и Subnets/IPv4
# это разные пути в git, и сводить их нельзя.
assert_eq "Subnets/IPv4/meta.lst
Subnets/ipv4/meta.lst" \
	"$(run 'Subnets/IPv4/meta.lst
Subnets/ipv4/meta.lst
')" "does not merge paths that differ outside the file name"

assert_exit 0 "exits successfully on empty input" sh -c "printf '' | sh $CANON"

tt_test_summary
