#!/bin/sh
# Публикация dnsmasq.conf и сброс кэша dnsmasq в init-скрипте.
#
# Почему сброс кэша вообще проверяется. `routing up` пересоздаёт nft-таблицу
# с нуля (dump_ruleset начинается с `delete table`), поэтому все адреса,
# которые dnsmasq накопил в tt_bypass4/6, каждый раз пропадают. Наполнить
# наборы заново может ТОЛЬКО dnsmasq и ТОЛЬКО отвечая от upstream: ответ,
# выданный из его собственного кэша, в nftset не попадает. ПРОВЕРЕНО на живом
# роутере (OpenWrt 25.12.5, dnsmasq 2.93): после `trusttunnel restart` без
# правки списков адрес, лежавший в наборе, исчезал, а повторный nslookup
# отвечал из кэша и набор не восстанавливал. Клиент при этом бьёт по адресу,
# которого в наборе больше нет, и уходит НАПРЯМУЮ — обход молча мёртв до
# истечения TTL. Поэтому после каждого routing up кэш обязан быть сброшен.
. "$(dirname "$0")/lib.sh"

INIT="packages/luci-app-trusttunnel/root/etc/init.d/trusttunnel"

sandbox="$TT_TEST_TMP/sandbox"
bin="$sandbox/bin"
mkdir -p "$bin" "$sandbox/out" "$sandbox/confdir"

# Заглушки пишут свои вызовы в журнал: судить приходится по нему, потому что
# ни dnsmasq, ни procd на машине разработчика нет.
TT_CALLS="$sandbox/calls"
export TT_CALLS
: > "$TT_CALLS"

cat > "$bin/dnsmasq" <<'EOF'
#!/bin/sh
# Версия БЕЗ no-nftset: в этих сценариях публикация должна состояться.
[ "$1" = "--version" ] && echo "Dnsmasq version 2.93 nftset"
exit 0
EOF

cat > "$bin/killall" <<'EOF'
#!/bin/sh
echo "killall $*" >> "$TT_CALLS"
exit 0
EOF

cat > "$bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$sandbox/dnsmasq-init" <<'EOF'
#!/bin/sh
echo "dnsmasq-init $*" >> "$TT_CALLS"
exit 0
EOF

chmod +x "$bin/dnsmasq" "$bin/killall" "$bin/logger" "$sandbox/dnsmasq-init"
PATH="$bin:$PATH"
export PATH
TT_DNSMASQ_INIT="$sandbox/dnsmasq-init"
export TT_DNSMASQ_INIT

# На верхнем уровне init-скрипт только присваивает переменные и определяет
# функции, поэтому подключается без /etc/rc.common, procd и UCI.
# shellcheck disable=SC1090
. "$INIT"

OUTDIR="$sandbox/out"
# Поиск conf-dir спрашивает работающий dnsmasq и UCI — ни того, ни другого
# здесь нет, а к предмету теста он не относится.
dnsmasq_confdir() { printf '%s\n' "$sandbox/confdir"; }

calls() { cat "$TT_CALLS"; }
no_call() { grep -F "$1" "$TT_CALLS" 2>/dev/null || true; }

# --- Первая публикация --------------------------------------------------------
printf 'nftset=/a.example/4#inet#trusttunnel#tt_bypass4\n' > "$OUTDIR/dnsmasq.conf"
: > "$TT_CALLS"
link_dnsmasq
flush_dns_cache

assert_eq "nftset=/a.example/4#inet#trusttunnel#tt_bypass4" \
	"$(cat "$sandbox/confdir/trusttunnel.conf")" \
	"конфиг публикуется в conf-dir копией"
assert_contains "$(calls)" "dnsmasq-init restart" \
	"новый конфиг перезапускает dnsmasq"
# HUP после полного restart избыточен: тот уже поднял dnsmasq с пустым кэшем.
assert_eq "" "$(no_call 'killall -HUP')" \
	"после restart кэш повторно не сбрасывается"

# --- Повторное применение без изменения списков -------------------------------
# Это ровно то, что делает Save & Apply несписочной настройки, флап WAN и
# ручной restart: содержимое dnsmasq.conf то же, publish-снимок совпадает,
# dnsmasq не перезапускается — а наборы `routing up` уже обнулил.
: > "$TT_CALLS"
link_dnsmasq
flush_dns_cache

assert_eq "" "$(no_call 'dnsmasq-init restart')" \
	"неизменившийся конфиг dnsmasq не перезапускает"
assert_contains "$(calls)" "killall -HUP dnsmasq" \
	"но кэш сбрасывается, иначе наборы после routing up останутся пустыми"

# --- Режим full: публикация снимается -----------------------------------------
rm -f "$OUTDIR/dnsmasq.conf"
: > "$TT_CALLS"
link_dnsmasq

assert_eq "0" "$(ls "$sandbox/confdir" | grep -c . || true)" \
	"без dnsmasq.conf публикация снимается"
assert_contains "$(calls)" "dnsmasq-init restart" \
	"снятие публикации перезапускает dnsmasq"

tt_test_summary
