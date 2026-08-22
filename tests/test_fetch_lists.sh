#!/bin/sh
. "$(dirname "$0")/lib.sh"

FETCH=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/fetch-lists

# Подменяем curl: печатает содержимое файла-заготовки, код возврата из файла.
stub="$TT_TEST_TMP/bin"
mkdir -p "$stub"
cat > "$stub/fakecurl" <<'EOF'
#!/bin/sh
# Заглушка curl. Обязана понимать -o FILE: fetch-lists скачивает именно так,
# и заглушка, пишущая в stdout, провалила бы тест при верной реализации.
out=""
url=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o|--max-time|--retry) # ключи со значением
			[ "$1" = "-o" ] && out="$2"
			shift 2 ;;
		-*) shift ;;
		*)  url="$1"; shift ;;
	esac
done
name=${url##*/}
[ -f "$TT_STUB_DIR/$name" ] || exit 22
if [ -n "$out" ]; then
	cat "$TT_STUB_DIR/$name" > "$out"
else
	cat "$TT_STUB_DIR/$name"
fi
exit 0
EOF
chmod +x "$stub/fakecurl"

TT_STUB_DIR="$TT_TEST_TMP/stub"
mkdir -p "$TT_STUB_DIR"
export TT_STUB_DIR
export TT_CURL="$stub/fakecurl"
export TT_LISTS_BASE_URL="https://example.invalid/allow-domains"

cat > "$TT_TEST_TMP/rec.tsv" <<'EOF'
lists.source	Services/youtube.lst
lists.subnet	Subnets/IPv4/telegram.lst
lists.url	https://example.org/my.lst
EOF

printf 'youtube.com\n' > "$TT_STUB_DIR/youtube.lst"
printf '149.154.160.0/20\n' > "$TT_STUB_DIR/telegram.lst"
printf 'mysite.example\n' > "$TT_STUB_DIR/my.lst"

dir="$TT_TEST_TMP/lists"
out="$(sh "$FETCH" "$TT_TEST_TMP/rec.tsv" "$dir")"

assert_contains "$out" "ok Services/youtube.lst" "reports successful fetch"
assert_eq "youtube.com" "$(cat "$dir/Services/youtube.lst")" "writes list content"
assert_eq "149.154.160.0/20" "$(cat "$dir/Subnets/IPv4/telegram.lst")" "writes subnet list"
assert_eq "mysite.example" "$(cat "$dir/custom/my.lst")" "writes custom url list under custom/"

# Повторный запуск с тем же содержимым — unchanged, файл не перезаписан.
before=$(cat "$dir/Services/youtube.lst")
out2="$(sh "$FETCH" "$TT_TEST_TMP/rec.tsv" "$dir")"
assert_contains "$out2" "unchanged Services/youtube.lst" "reports unchanged content"
assert_eq "$before" "$(cat "$dir/Services/youtube.lst")" "keeps identical file"

# Пустой ответ не должен затирать существующий файл.
: > "$TT_STUB_DIR/youtube.lst"
out3="$(sh "$FETCH" "$TT_TEST_TMP/rec.tsv" "$dir")"
assert_contains "$out3" "fail Services/youtube.lst" "reports empty response as failure"
assert_eq "youtube.com" "$(cat "$dir/Services/youtube.lst")" "keeps previous copy on empty response"

# Сетевая ошибка не должна затирать существующий файл.
rm -f "$TT_STUB_DIR/telegram.lst"
sh "$FETCH" "$TT_TEST_TMP/rec.tsv" "$dir" >/dev/null 2>&1
assert_eq "149.154.160.0/20" "$(cat "$dir/Subnets/IPv4/telegram.lst")" "keeps previous copy on transport error"

# Обрыв при наличии копии НЕ должен валить прогон: иначе ночной cron будет
# рапортовать отказ каждый раз, когда один список ненадолго недоступен.
assert_exit 0 "keeps exit 0 when a failed source has a fallback copy" \
	sh "$FETCH" "$TT_TEST_TMP/rec.tsv" "$dir"

# URL с завершающим слэшем даёт пустой basename; это отказ, а не ложный ok.
printf 'lists.url\thttps://example.org/mylist/\n' > "$TT_TEST_TMP/slash.tsv"
out5="$(sh "$FETCH" "$TT_TEST_TMP/slash.tsv" "$TT_TEST_TMP/lists-slash" 2>/dev/null || true)"
assert_contains "$out5" "fail custom/" "rejects a URL whose basename is empty"

# Полный провал без предыдущей копии — ненулевой код возврата.
printf 'lists.source\tServices/nope.lst\n' > "$TT_TEST_TMP/bad.tsv"
assert_exit 1 "fails when a source cannot be fetched at all" \
	sh "$FETCH" "$TT_TEST_TMP/bad.tsv" "$TT_TEST_TMP/lists-empty"

tt_test_summary
