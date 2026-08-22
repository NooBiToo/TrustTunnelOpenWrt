#!/bin/sh
# Прогрев наборов обхода своими доменами.
. "$(dirname "$0")/lib.sh"

WARM=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/warm-sets

bin="$TT_TEST_TMP/bin"
mkdir -p "$bin"
cat > "$bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$bin/logger"
PATH="$bin:$PATH"
export PATH

# Заглушка резолвера: пишет запрошенные имена в журнал и падает первые
# TT_FAKE_FAIL вызовов, чтобы можно было проверить ожидание dnsmasq.
fake="$TT_TEST_TMP/fake-nslookup"
cat > "$fake" <<'EOF'
#!/bin/sh
echo "$1" >> "$TT_FAKE_LOG"
if [ -n "${TT_FAKE_FAIL:-}" ]; then
	n=$(cat "$TT_FAKE_STATE" 2>/dev/null || echo 0)
	n=$((n + 1))
	echo "$n" > "$TT_FAKE_STATE"
	[ "$n" -le "$TT_FAKE_FAIL" ] && exit 1
fi
exit 0
EOF
chmod +x "$fake"

TT_NSLOOKUP="$fake"
TT_WARM_SLEEP=0
export TT_NSLOOKUP TT_WARM_SLEEP

list="$TT_TEST_TMP/own.domains"
printf 'a.example\nb.example\nc.example\n' > "$list"

# --- Обычный прогрев ----------------------------------------------------------
TT_FAKE_LOG="$TT_TEST_TMP/log1"; export TT_FAKE_LOG
: > "$TT_FAKE_LOG"
out=$(sh "$WARM" "$list")

assert_contains "$out" "warmed 3" "резолвит каждый свой домен"
assert_contains "$out" "failed 0" "без отказов"
assert_eq "a.example b.example c.example" "$(tr '\n' ' ' < "$TT_FAKE_LOG" | sed 's/ $//')" \
	"каждый домен спрошен ровно один раз и в порядке файла"

# --- Резолвер поднимается не сразу --------------------------------------------
# `/etc/init.d/dnsmasq restart` возвращает управление до того как dnsmasq снова
# слушает, поэтому первые попытки обязаны повторяться, а не отбрасывать прогрев.
TT_FAKE_LOG="$TT_TEST_TMP/log2"; export TT_FAKE_LOG
TT_FAKE_STATE="$TT_TEST_TMP/state2"; export TT_FAKE_STATE
: > "$TT_FAKE_LOG"
TT_FAKE_FAIL=2 sh "$WARM" "$list" > "$TT_TEST_TMP/out2"
out=$(cat "$TT_TEST_TMP/out2")

assert_contains "$out" "warmed 3" "дожидается резолвера и прогревает всё"
assert_eq "3" "$(grep -c '^a\.example$' "$TT_FAKE_LOG")" \
	"первый домен переспрашивается, пока резолвер не ответит"

# --- Резолвер не отвечает вовсе -----------------------------------------------
# Отказ прогрева не должен быть отказом применения настроек: наборы наполнятся
# лениво, как наполнялись до его появления.
TT_FAKE_LOG="$TT_TEST_TMP/log3"; export TT_FAKE_LOG
TT_FAKE_STATE="$TT_TEST_TMP/state3"; export TT_FAKE_STATE
: > "$TT_FAKE_LOG"
TT_FAKE_FAIL=99 TT_WARM_TRIES=3 sh "$WARM" "$list" > "$TT_TEST_TMP/out3" 2>&1
assert_eq "0" "$?" "выходит успешно, даже когда резолвер молчит"
assert_eq "3" "$(grep -c . "$TT_FAKE_LOG")" "не пытается больше отведённого числа раз"
assert_eq "" "$(grep 'warmed' "$TT_TEST_TMP/out3" || true)" "и не заявляет прогрев, которого не было"

# --- Нечего прогревать --------------------------------------------------------
TT_FAKE_LOG="$TT_TEST_TMP/log4"; export TT_FAKE_LOG
: > "$TT_FAKE_LOG"
: > "$TT_TEST_TMP/empty"
assert_exit 0 "пустой список — не ошибка" sh "$WARM" "$TT_TEST_TMP/empty"
assert_exit 0 "отсутствующий файл — не ошибка" sh "$WARM" "$TT_TEST_TMP/nope"
assert_eq "" "$(cat "$TT_FAKE_LOG")" "и ни одного запроса"

# Проверяется НЕнулевой выход, а не конкретный код: при отказе ${1:?} bash
# выходит с 1, а dash — с 2, и CI гоняет тесты именно на dash. Важно здесь
# только то, что отказ не молчаливый.
if sh "$WARM" >/dev/null 2>&1; then failed_ok=no; else failed_ok=yes; fi
assert_eq "yes" "$failed_ok" "без аргумента — отказ, а не молчаливый успех"

tt_test_summary
