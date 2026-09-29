#!/bin/sh
# Замер скорости: пинг, загрузка, отдача — напрямую и через туннель.
. "$(dirname "$0")/lib.sh"

S=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/speedtest

bin="$TT_TEST_TMP/bin"
mkdir -p "$bin"

# Заглушка curl. Различает три запроса по адресу и печатает то, что curl
# напечатал бы по -w. Пауза нужна, чтобы потоки не крутились вхолостую:
# настоящий curl тоже занимает время, а тест без неё гоняет тысячи процессов.
cat > "$bin/curl" <<'EOF'
#!/bin/sh
echo "$*" >> "$TT_FAKE_LOG"
sleep "${TT_FAKE_SLEEP:-0.2}"
case "$*" in
	*"bytes=0"*) printf '0.100 0.150' ;;
	*"/__up"*)   printf '1000000' ;;
	*)           printf '2000000' ;;
esac
exit 0
EOF
chmod +x "$bin/curl"

# Пустой ip: WAN-устройство не находится, живая скорость остаётся нулём, а
# итог считается по curl и от счётчиков не зависит.
cat > "$bin/ip" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$bin/ip"

TT_CURL="$bin/curl"
TT_IP="$bin/ip"
TT_SPEEDTEST_SECS=1
TT_SPEEDTEST_STREAMS=2
TT_SPEEDTEST_PINGS=3
TT_SPEEDTEST_TICK=0.1
TT_FAKE_LOG="$TT_TEST_TMP/curl.log"
TT_SYSFS="$TT_TEST_TMP/sys"
export TT_CURL TT_IP TT_SPEEDTEST_SECS TT_SPEEDTEST_STREAMS TT_SPEEDTEST_PINGS \
	TT_SPEEDTEST_TICK TT_FAKE_LOG TT_SYSFS

mkdir -p "$TT_SYSFS/tun9/statistics"
echo 0 > "$TT_SYSFS/tun9/statistics/rx_bytes"
echo 0 > "$TT_SYSFS/tun9/statistics/tx_bytes"

# Значение ключа из вывода status.
val() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { v = $2 } END { print v }'; }
# Больше нуля, числом.
positive() { awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9.]+$/ && v + 0 > 0) }'; }

# --- Пустое состояние -----------------------------------------------------------
D="$TT_TEST_TMP/idle"
out=$(sh "$S" status "$D")
assert_eq "idle" "$(val "$out" phase)" "без замера фаза idle"
assert_eq "0" "$(val "$out" running)" "без замера ничего не запущено"

# --- Полный прогон без туннеля -------------------------------------------------
D="$TT_TEST_TMP/direct-only"
mkdir -p "$D"
sh "$S" run "$D" - </dev/null
out=$(sh "$S" status "$D")
assert_eq "done" "$(val "$out" phase)" "прогон заканчивается фазой done"
assert_eq "50.0" "$(val "$out" direct.ping)" "пинг — ответ минус рукопожатие, в мс"
assert_eq "0.0" "$(val "$out" direct.jitter)" "ровные замеры дают нулевой jitter"
positive "$(val "$out" direct.down)"; assert_eq "0" "$?" "загрузка напрямую больше нуля"
positive "$(val "$out" direct.up)";   assert_eq "0" "$?" "отдача напрямую больше нуля"
assert_eq "1" "$(val "$out" tunnel.skipped)" "без туннеля его замер пропущен"
assert_eq "" "$(val "$out" tunnel.down)" "без туннеля цифр по туннелю нет"

# Обращения без устройства: прямой замер не должен привязываться к интерфейсу.
assert_eq "0" "$(grep -c -- '--interface' "$TT_FAKE_LOG")" "прямой замер не привязан к интерфейсу"

# --- Полный прогон с туннелем --------------------------------------------------
D="$TT_TEST_TMP/both"
mkdir -p "$D"
: > "$TT_FAKE_LOG"
sh "$S" run "$D" tun9 </dev/null
out=$(sh "$S" status "$D")
assert_eq "done" "$(val "$out" phase)" "прогон с туннелем заканчивается фазой done"
positive "$(val "$out" tunnel.down)"; assert_eq "0" "$?" "загрузка через туннель больше нуля"
positive "$(val "$out" tunnel.up)";   assert_eq "0" "$?" "отдача через туннель больше нуля"
assert_eq "50.0" "$(val "$out" tunnel.ping)" "пинг через туннель"
assert_eq "" "$(val "$out" tunnel.skipped)" "с туннелем ничего не пропущено"
assert_contains "$(cat "$TT_FAKE_LOG")" "--interface tun9" "замер туннеля привязан к его устройству"

# --- Запуск в фоне, отказ при повторном, остановка -----------------------------
D="$TT_TEST_TMP/bg"
TT_FAKE_SLEEP=3; export TT_FAKE_SLEEP
out=$(sh "$S" start "$D" -)
assert_eq "1" "$(val "$(sh "$S" status "$D")" running)" "после start замер идёт"
out=$(sh "$S" start "$D" -; echo "rc=$?")
assert_contains "$out" "already running" "второй start отказывает"
assert_contains "$out" "rc=1" "второй start завершается ошибкой"

sh "$S" stop "$D"
i=0
while [ "$(val "$(sh "$S" status "$D")" running)" = "1" ] && [ $i -lt 30 ]; do
	sleep 0.2
	i=$((i + 1))
done
out=$(sh "$S" status "$D")
assert_eq "0" "$(val "$out" running)" "после stop замер не идёт"
assert_eq "stopped" "$(val "$out" phase)" "после stop фаза stopped"
unset TT_FAKE_SLEEP

# --- Оборванный замер ----------------------------------------------------------
# Процесс умер, не дописав фазу: статус обязан сказать об этом, а не показывать
# вечный «загрузка идёт».
D="$TT_TEST_TMP/dead"
mkdir -p "$D"
printf 'phase\tdownload\n' > "$D/state.tsv"
echo 999999 > "$D/pid"
out=$(sh "$S" status "$D")
assert_eq "0" "$(val "$out" running)" "мёртвый процесс не считается работающим"
assert_eq "interrupted" "$(val "$out" error)" "оборванный замер помечен ошибкой"

tt_test_summary
