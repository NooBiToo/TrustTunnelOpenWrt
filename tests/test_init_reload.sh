#!/bin/sh
# Применение настроек: apply_settings и сохранение маршрутизации на перезапуске.
#
# ЗАЧЕМ. Save & Apply приходит в reload_service. Раньше тот безусловно звал
# restart, и любая правка убивала клиента: туннель рвался на несколько секунд,
# а вместе с nft-таблицей на это время исчезала маркировка, так что помеченный
# трафик LAN успевал уйти НАПРЯМУЮ — то есть обычное сохранение настроек само
# открывало утечку, от которой этот пакет и защищает.
#
# Теперь reload_service спрашивает classify_change, что именно требуется, и на
# перезапуске маршрутизация переживает цикл stop+start. Здесь проверяются оба
# решения и, что важнее, их откаты: неудача на дешёвом пути обязана
# заканчиваться полным перезапуском, а прерванный старт — настоящим разбором
# маршрутизации, иначе таблица и правило по отметке остались бы висеть,
# указывая на то, чего больше нет.
. "$(dirname "$0")/lib.sh"

INIT="packages/luci-app-trusttunnel/root/etc/init.d/trusttunnel"

sandbox="$TT_TEST_TMP/sandbox"
bin="$sandbox/bin"
mkdir -p "$bin" "$sandbox/lib" "$sandbox/out"

TT_CALLS="$sandbox/calls"
export TT_CALLS

# Заглушки-скрипты пишут свои вызовы в журнал: ни procd, ни UCI, ни настоящего
# routing на машине разработчика нет, судить приходится по нему.
cat > "$sandbox/lib/routing" <<'EOF'
#!/bin/sh
echo "routing $1" >> "$TT_CALLS"
[ "$1" = "up" ] && exit "${ROUTING_UP_RC:-0}"
exit 0
EOF

cat > "$sandbox/lib/uci-export" <<'EOF'
#!/bin/sh
[ "${UCI_EXPORT_RC:-0}" = "0" ] || exit "$UCI_EXPORT_RC"
cat "$TT_NEXT"
EOF

# Сертификат в records не попадает (PEM многострочный), поэтому apply_settings
# сверяет его отдельным вызовом uci.
cat > "$bin/uci" <<'EOF'
#!/bin/sh
cat "$TT_CERT_UCI" 2>/dev/null
exit 0
EOF

chmod +x "$sandbox/lib/routing" "$sandbox/lib/uci-export" "$bin/uci"
PATH="$bin:$PATH"
export PATH

# shellcheck disable=SC1090
. "$INIT"

# Пути вычислены на верхнем уровне init-скрипта от /var, поэтому
# переопределяются здесь оба: и каталог, и файл записи внутри него.
OUTDIR="$sandbox/out"
RECORDS="$OUTDIR/settings.tsv"
LIBDIR="$sandbox/lib"

TT_NEXT="$sandbox/next.tsv"
TT_CERT_UCI="$sandbox/cert_uci"
export TT_NEXT TT_CERT_UCI
: > "$TT_CERT_UCI"

# Всё, что за пределами предмета проверки, заменяется журналируемыми
# заглушками. regenerate подменяется в том числе потому, что настоящий
# перекладывает records сам — а тесту нужно видеть, дошло ли до него дело.
restart() { echo "restart keep_routing=${_TT_KEEP_ROUTING:-0}" >> "$TT_CALLS"; }
regenerate() {
	echo "regenerate" >> "$TT_CALLS"
	[ "${REGEN_RC:-0}" = "0" ] || return "$REGEN_RC"
	cp "$TT_NEXT" "$RECORDS"
}
running() { return "${RUNNING_RC:-0}"; }
link_dnsmasq() { echo "link_dnsmasq" >> "$TT_CALLS"; }
flush_dns_cache() { echo "flush_dns_cache" >> "$TT_CALLS"; }
warm_sets() { echo "warm_sets" >> "$TT_CALLS"; }
unlink_dnsmasq() { echo "unlink_dnsmasq" >> "$TT_CALLS"; }
logger() { :; }

calls() { tr '\n' ' ' < "$TT_CALLS" | sed 's/ $//'; }
no_call() { grep -F "$1" "$TT_CALLS" 2>/dev/null || true; }

base_records() {
	cat <<'EOF'
main.enabled	1
main.mode	selective
endpoint.hostname	a.example
network.table	880
lists.source	Russia/inside-dnsmasq-nfset.lst
EOF
}

# Готовит применённое состояние и предполагаемое новое, чистит журнал.
setup() {
	base_records > "$RECORDS"
	base_records > "$TT_NEXT"
	: > "$TT_CALLS"
	unset ROUTING_UP_RC REGEN_RC UCI_EXPORT_RC RUNNING_RC _TT_KEEP_ROUTING
	export ROUTING_UP_RC REGEN_RC UCI_EXPORT_RC
}

# --- Дешёвый путь -------------------------------------------------------------

# Правка списков в селективном режиме до client.toml не доходит, поэтому
# клиента трогать не за что: перегенерировать, перезалить в ядро, перепривязать
# маршрут на ЖИВОЕ устройство и сбросить кэш dnsmasq — наборы tt_bypass
# обнулились вместе с пересозданной таблицей.
setup
printf 'lists.source\tServices/youtube.lst\n' >> "$TT_NEXT"
apply_settings

assert_eq "" "$(no_call 'restart')" \
	"правка списков не перезапускает клиента"
assert_contains "$(calls)" "routing up" \
	"но правила перезаливаются в ядро"
assert_contains "$(calls)" "routing reattach" \
	"и маршрут перепривязывается к живому устройству"
assert_contains "$(calls)" "link_dnsmasq" \
	"публикация dnsmasq обновляется"
assert_contains "$(calls)" "flush_dns_cache" \
	"кэш сбрасывается, иначе наборы после routing up останутся пустыми"

# Запись о применённом состоянии обязана догонять: следующее применение
# сравнивает с ней, и без обновления та же правка считалась бы изменением
# каждый раз.
assert_contains "$(cat "$RECORDS")" "Services/youtube.lst" \
	"запись о применённом состоянии обновлена"

# --- Ничего применять не нужно ------------------------------------------------

# Расписание автообновления читает cron во время работы. Ни клиент, ни ядро об
# этом ключе не знают, поэтому верное число действий — ноль.
setup
printf 'lists.auto_update\t0\n' >> "$TT_NEXT"
apply_settings

assert_eq "" "$(calls)" \
	"правка расписания не делает ничего"
assert_contains "$(cat "$RECORDS")" "lists.auto_update" \
	"но запись обновлена, иначе правка участвовала бы в каждом следующем сравнении"

# --- Перезапуск с сохранением маршрутизации -----------------------------------

setup
sed -i 's/a.example/b.example/' "$TT_NEXT"
apply_settings

assert_contains "$(calls)" "restart keep_routing=1" \
	"смена адреса сервера перезапускает клиента, не разбирая маршрутизацию"

# --- Перезапуск с полным разбором ---------------------------------------------

# Номер таблицы и отметка — единственные значения, по которым маршрутизация
# снимается. Сохранить прежнюю и поднять новую значило бы оставить старую
# таблицу и старое правило висеть навсегда.
setup
sed -i 's/network.table\t880/network.table\t881/' "$TT_NEXT"
apply_settings

assert_contains "$(calls)" "restart keep_routing=0" \
	"смена номера таблицы разбирает маршрутизацию полностью"

setup
sed -i 's/main.enabled\t1/main.enabled\t0/' "$TT_NEXT"
apply_settings

assert_contains "$(calls)" "restart keep_routing=0" \
	"выключение службы разбирает маршрутизацию полностью"

# --- Сертификат ---------------------------------------------------------------

# Единственное значение схемы, которого в records нет: PEM многострочный.
# Без отдельной сверки смена сертификата не применялась бы вовсе — records
# при ней не меняется, и дешёвый путь решил бы, что делать нечего.
setup
printf -- '-----BEGIN CERTIFICATE-----\nnew\n-----END CERTIFICATE-----\n' > "$TT_CERT_UCI"
apply_settings

assert_contains "$(calls)" "restart" \
	"смена сертификата перезапускает клиента, хотя records не изменился"

# И наоборот: неизменный сертификат не должен сам по себе вызывать перезапуск.
setup
printf -- '-----BEGIN CERTIFICATE-----\nsame\n-----END CERTIFICATE-----\n' > "$TT_CERT_UCI"
cp "$TT_CERT_UCI" "$OUTDIR/endpoint.pem"
printf 'lists.source\tServices/youtube.lst\n' >> "$TT_NEXT"
apply_settings

assert_eq "" "$(no_call 'restart')" \
	"неизменный сертификат не мешает дешёвому пути"
rm -f "$OUTDIR/endpoint.pem"
: > "$TT_CERT_UCI"

# --- Откаты -------------------------------------------------------------------

# Отказ на дешёвом пути обязан заканчиваться полным перезапуском: правила в
# ядре в этот момент в неизвестном состоянии, и оставить всё как есть значило
# бы показывать работающую службу поверх недогруженной таблицы.
setup
printf 'lists.source\tServices/youtube.lst\n' >> "$TT_NEXT"
ROUTING_UP_RC=1
apply_settings

assert_contains "$(calls)" "restart keep_routing=0" \
	"провал routing up откатывает к полному перезапуску"

setup
printf 'lists.source\tServices/youtube.lst\n' >> "$TT_NEXT"
REGEN_RC=1
apply_settings

assert_contains "$(calls)" "restart keep_routing=0" \
	"провал перегенерации откатывает к полному перезапуску"

# Сравнивать не с чем — это обычный старт, а не применение поверх известного
# состояния. /var на OpenWrt в tmpfs, поэтому после перезагрузки записи нет.
setup
rm -f "$RECORDS"
apply_settings

assert_contains "$(calls)" "restart" \
	"без записи о применённом состоянии — полный путь"

# Служба не работает: применять поверх ничего нечего.
setup
printf 'lists.source\tServices/youtube.lst\n' >> "$TT_NEXT"
RUNNING_RC=1
apply_settings

assert_contains "$(calls)" "restart" \
	"остановленная служба применяется полным путём"
unset RUNNING_RC

# Не удалось выгрузить UCI — сравнивать не с чем, решение принимать не на чем.
setup
UCI_EXPORT_RC=1
apply_settings

assert_contains "$(calls)" "restart" \
	"провал выгрузки UCI откатывает к полному перезапуску"
assert_eq "0" "$(ls "$OUTDIR" | grep -c 'settings.tsv.next' || true)" \
	"и не оставляет за собой недописанный файл с паролем внутри"

# --- Маршрутизация переживает перезапуск --------------------------------------

# Проверяется настоящий stop_service, а не заглушка: именно он решает, звать
# ли routing down.
setup
_TT_RESTARTING=1
_TT_KEEP_ROUTING=1
stop_service

assert_eq "" "$(no_call 'routing down')" \
	"на перезапуске с сохранением маршрутизация не разбирается"

setup
_TT_RESTARTING=0
_TT_KEEP_ROUTING=0
stop_service

assert_contains "$(calls)" "routing down" \
	"обычный stop разбирает маршрутизацию как раньше"
assert_contains "$(calls)" "unlink_dnsmasq" \
	"и снимает публикацию dnsmasq"

# Прерванный старт. Расчёт «разбирать не нужно» держится на том, что start
# поднимет всё заново; если он не дошёл до конца — служба выключена, а
# таблица, правило по отметке и blackhole остались бы висеть, указывая на
# несуществующий туннель. Помеченный трафик уходил бы в blackhole при
# выключенном обходе, и в интерфейсе это выглядело бы как «нет интернета».
setup
_TT_RESTARTING=1
_TT_KEEP_ROUTING=1
abort_restart_cleanup

assert_contains "$(calls)" "routing down" \
	"прерванный старт разбирает сохранённую маршрутизацию"
assert_contains "$(calls)" "unlink_dnsmasq" \
	"и снимает публикацию dnsmasq"
assert_eq "0" "${_TT_KEEP_ROUTING}" \
	"признак сбрасывается, чтобы повторный вызов не разбирал дважды"

tt_test_summary
