# Чтение records-файла: строки вида "section.option<TAB>value".
# Требует TT_RECORDS с путём к файлу. Подключать через точку.
#
# Проверка "${TT_RECORDS:?...}" стоит в НАЧАЛЕ КАЖДОЙ функции, а не как
# отдельная строка на верхнем уровне файла. Все четыре реальных вызывающих
# (gen-config, gen-lists, fetch-lists, routing) делают `. records.sh` ДО того,
# как присваивают TT_RECORDS из своего аргумента — так проверка на верхнем
# уровне срабатывала бы при каждом подключении файла, ещё до того как
# вызывающий успел бы задать переменную, и валила бы все четыре генератора
# на пустом месте. Проверка внутри функций достигает той же цели —
# несконфигурированный TT_RECORDS падает с понятной ошибкой, а не тихо
# превращается в пустое имя файла, на котором awk молча читает stdin, — но
# срабатывает в момент фактического обращения, когда TT_RECORDS уже обязан
# быть установлен.

tt_list() {
	: "${TT_RECORDS:?TT_RECORDS is not set}"
	awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$TT_RECORDS"
}

tt_get() {
	: "${TT_RECORDS:?TT_RECORDS is not set}"
	_v=$(awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$TT_RECORDS")
	if [ -n "$_v" ]; then
		printf '%s\n' "$_v"
	else
		printf '%s\n' "${2-}"
	fi
}

tt_bool() {
	: "${TT_RECORDS:?TT_RECORDS is not set}"
	_v=$(awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$TT_RECORDS")
	[ -n "$_v" ] || _v="${2-0}"
	if [ "$_v" = "1" ]; then printf 'true\n'; else printf 'false\n'; fi
}

tt_count() {
	: "${TT_RECORDS:?TT_RECORDS is not set}"
	awk -F'\t' -v k="$1" '$1 == k { n++ } END { print n + 0 }' "$TT_RECORDS"
}
