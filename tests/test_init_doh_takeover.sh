#!/bin/sh
# Захват и возврат resolver_url штатного https-dns-proxy.
#
# ЗАЧЕМ. Резолвер, заданный в наших настройках, обслуживал только домены из
# списков: генератор выдавал `server=/домен/127.0.0.1#5460`, а весь остальной
# DNS сети шёл туда, куда его направил штатный https-dns-proxy — обычно в
# Cloudflare. Со стороны это выглядело как незаработавшая настройка: любая
# проверялка в списках не лежит и показывает чужой резолвер.
#
# Забрать общий DNS своим снипетом в conf-dir нельзя: ПРОВЕРЕНО на стенде, что
# wildcard-домен `/#/` приоритета над бездоменными `server=` не имеет и
# попадает с ними в один пул — при `server=127.0.0.1#5053` рядом с
# `server=/#/127.0.0.1#5460` отвечал Cloudflare. Поэтому владение забирается
# через единственное чужое значение — resolver_url, — а работа с конфигом
# dnsmasq остаётся штатному сервису: у него для этого есть dhcp_backup
# create/restore.
#
# Главная ошибка, которую здесь легко сделать, — отравить бэкап. Смена URL в
# настройках даёт класс `restart`, при рестарте освобождение пропускается, и
# apply приходит поверх собственного захвата. Сохранив «исходным» наш же
# прежний URL, он навсегда лишил бы пользователя его настроек. На это здесь
# отдельная проверка.
. "$(dirname "$0")/lib.sh"

INIT="packages/luci-app-trusttunnel/root/etc/init.d/trusttunnel"

sandbox="$TT_TEST_TMP/sandbox"
bin="$sandbox/bin"
mkdir -p "$bin" "$sandbox/out" "$sandbox/state"

TT_CALLS="$sandbox/calls"
export TT_CALLS
: > "$TT_CALLS"

# Мини-uci на плоском файле, поля разделены пробелом: ни ключи, ни URL пробелов
# не содержат. Понимает ровно то подмножество, которым пользуется захват: show,
# get, set, add, delete, commit. Вывод show повторяет настоящий uci, включая
# кавычки у значений опций и их отсутствие у типа секции, — разбор секций в
# захвате опирается именно на это различие.
TT_UCI_DB="$sandbox/uci.db"
export TT_UCI_DB
cat > "$bin/uci" <<'EOF'
#!/bin/sh
db="$TT_UCI_DB"
[ -f "$db" ] || : > "$db"
[ "$1" = "-q" ] && shift
cmd="$1"; shift

# Адрес вида pkg.@тип[N].опция uci принимает наравне с именем секции, и захват
# пользуется именно им: реальных имён анонимных секций uci не печатает даже с
# -n, что проверено на живом роутере. Здесь такой адрес разворачивается в имя
# секции из базы по порядковому номеру.
resolve() {
	case "$1" in
		*.@*)
			_pkg=${1%%.*}
			_rest=${1#*.@}
			_type=${_rest%%\[*}
			_idx=${_rest#*\[}; _idx=${_idx%%\]*}
			_tail=${_rest#*\]}
			_sec=$(awk -v p="$_pkg" -v t="$_type" -v i="$_idx" '
				$2 == "section" && $3 == t && index($1, p ".") == 1 {
					if (n + 0 == i + 0) { sub(/^[^.]*\./, "", $1); print $1; exit }
					n++
				}' "$db")
			[ -n "$_sec" ] || { printf '%s\n' "$1"; return 0; }
			printf '%s.%s%s\n' "$_pkg" "$_sec" "$_tail"
			;;
		*) printf '%s\n' "$1" ;;
	esac
}

case "$cmd" in
	show)
		awk -v pkg="$1" -v q="'" '
			$1 == pkg || index($1, pkg ".") == 1 {
				if ($2 == "section") printf "%s=%s\n", $1, $3
				else printf "%s=%s%s%s\n", $1, q, $2, q
			}' "$db"
		;;
	get)
		awk -v k="$(resolve "$1")" '$1 == k && $2 != "section" { print $2; f = 1 }
			END { exit(f ? 0 : 1) }' "$db"
		;;
	set)
		k=$(resolve "${1%%=*}"); v=${1#*=}
		awk -v k="$k" '$1 != k' "$db" > "$db.tmp"
		printf '%s %s\n' "$k" "$v" >> "$db.tmp"
		mv "$db.tmp" "$db"
		;;
	add)
		n=$(awk '$2 == "section" { c++ } END { print c + 1 }' "$db")
		printf '%s.cfgnew%s section %s\n' "$1" "$n" "$2" >> "$db"
		printf 'cfgnew%s\n' "$n"
		;;
	delete)
		awk -v k="$(resolve "$1")" '$1 != k && index($1, k ".") != 1' "$db" > "$db.tmp"
		mv "$db.tmp" "$db"
		;;
	commit)
		echo "uci commit $1" >> "$TT_CALLS"
		;;
esac
exit 0
EOF

cat > "$bin/logger" <<'EOF'
#!/bin/sh
shift 2
echo "logger $*" >> "$TT_CALLS"
exit 0
EOF

# Заглушка их init-скрипта. Отвечает на `running` по TT_DOH_RUNNING: захват
# обязан различать «сервис уже работал» и «мы его подняли», иначе возврат либо
# оставит его работать, либо погасит чужой работающий сервис.
cat > "$sandbox/doh-init" <<'EOF'
#!/bin/sh
echo "doh-init $*" >> "$TT_CALLS"
if [ "$1" = "running" ]; then
	[ "${TT_DOH_RUNNING:-0}" = "1" ] && exit 0
	exit 1
fi
exit 0
EOF

# Бинарник прокси: захвату нужен только факт его исполнимости, сам он не
# запускается. Файл не пустой намеренно — в Git Bash на Windows пустой файл бит
# исполнения не получает, и проверка -x была бы ложноотрицательной.
printf '#!/bin/sh\nexit 0\n' > "$sandbox/https-dns-proxy"

chmod +x "$bin/uci" "$bin/logger" "$sandbox/doh-init" "$sandbox/https-dns-proxy"
PATH="$bin:$PATH"
export PATH
TT_DOH_INIT="$sandbox/doh-init"
TT_DOH_BIN="$sandbox/https-dns-proxy"
TT_STATE_DIR="$sandbox/state"
export TT_DOH_INIT TT_DOH_BIN TT_STATE_DIR

# На верхнем уровне init-скрипт только присваивает переменные и определяет
# функции, поэтому подключается без /etc/rc.common, procd и UCI.
# shellcheck disable=SC1090
. "$INIT"

OUTDIR="$sandbox/out"
RECORDS="$sandbox/settings.tsv"

calls() { cat "$TT_CALLS"; }
url_of() { uci -q get "https-dns-proxy.$1.resolver_url"; }
# Табы в состоянии заменяются пробелами, чтобы ассерты не зависели от
# литерального таба в исходнике теста. Отсутствие файла — обычный случай, а не
# ошибка: перенаправление на несуществующий файл шумит в stderr, поэтому
# проверяется заранее.
state_lines() {
	[ -f "$DOH_STATE" ] || return 0
	tr '\t' ' ' < "$DOH_STATE"
}

# Два инстанса с разными резолверами — ровно то, что ставит пакет
# https-dns-proxy по умолчанию.
reset_uci() {
	cat > "$TT_UCI_DB" <<'EOF'
https-dns-proxy.cfg01 section https-dns-proxy
https-dns-proxy.cfg01.resolver_url https://cloudflare-dns.com/dns-query
https-dns-proxy.cfg01.listen_port 5053
https-dns-proxy.cfg01.bootstrap_dns 1.1.1.1,1.0.0.1
https-dns-proxy.cfg02 section https-dns-proxy
https-dns-proxy.cfg02.resolver_url https://dns.google/dns-query
https-dns-proxy.cfg02.listen_port 5054
https-dns-proxy.cfg02.bootstrap_dns 8.8.8.8,8.8.4.4
EOF
}

# Четвёртый параметр через ${4-...}, а не ${4:-...}: пустой URL — отдельный
# проверяемый случай, и подстановка значения по умолчанию скрыла бы его.
records() {
	{
		printf 'main.mode\t%s\n' "${2:-selective}"
		printf 'network.list_dns\t%s\n' "${3:-doh}"
		printf 'network.doh_network\t%s\n' "${1:-1}"
		printf 'network.list_doh_url\t%s\n' "${4-https://dns.nextdns.io/66db2b}"
	} > "$RECORDS"
}

reset_all() {
	reset_uci
	records "$@"
	rm -f "$DOH_STATE"
	: > "$TT_CALLS"
}

# --- Когда захват вообще полагается ------------------------------------------

reset_all 1 selective doh
assert_exit 0 "захват полагается при doh_network=1 в режиме обхода" \
	doh_takeover_wanted

reset_all 0 selective doh
assert_exit 1 "снятый флаг — захвата нет" doh_takeover_wanted

reset_all 1 selective plain
assert_exit 1 "обычный DNS — захвата нет" doh_takeover_wanted

# Режим «всё через VPN» списки не использует, gen-lists там отказывается
# работать вовсе. Захватывать общий DNS ради несуществующих строк server=
# незачем — и по той же причине в этом режиме не должен подниматься наш
# инстанс на 5460, что до сих пор происходило.
reset_all 1 full doh
assert_exit 1 "режим «всё через VPN» — захвата нет" doh_takeover_wanted

# --- Захват -------------------------------------------------------------------

reset_all
TT_DOH_RUNNING=1 doh_takeover_apply

assert_eq "https://dns.nextdns.io/66db2b" "$(url_of cfg01)" \
	"первый инстанс переведён на наш резолвер"
# Второй инстанс тоже обязан уйти на наш резолвер. Их init не знает опции
# disabled — config_foreach start_instance поднимает каждую секцию без
# условий, — поэтому оставить второй с Google значило бы отдавать ему часть
# запросов: dnsmasq держит все бездоменные server= в одном пуле.
assert_eq "https://dns.nextdns.io/66db2b" "$(url_of cfg02)" \
	"второй инстанс тоже переведён, иначе часть запросов уйдёт мимо"
assert_contains "$(calls)" "uci commit https-dns-proxy" "изменения закоммичены"
assert_contains "$(calls)" "doh-init restart" "работавший сервис перезапущен"
assert_contains "$(state_lines)" "saved cfg01 https://cloudflare-dns.com/dns-query" \
	"исходный URL первого инстанса сохранён"
assert_contains "$(state_lines)" "saved cfg02 https://dns.google/dns-query" \
	"исходный URL второго инстанса сохранён"
assert_contains "$(state_lines)" "running 1" "запомнили, что сервис работал"
assert_contains "$(state_lines)" "applied https://dns.nextdns.io/66db2b" \
	"записанный нами URL запомнен для сверки при возврате"

# --- Повторный захват с новым URL --------------------------------------------

records 1 selective doh https://dns.nextdns.io/aaaaaa
: > "$TT_CALLS"
TT_DOH_RUNNING=1 doh_takeover_apply

assert_eq "https://dns.nextdns.io/aaaaaa" "$(url_of cfg01)" \
	"повторный захват применяет новый URL"
assert_contains "$(state_lines)" "saved cfg01 https://cloudflare-dns.com/dns-query" \
	"исходный URL при повторном захвате НЕ перезаписан"
assert_contains "$(state_lines)" "applied https://dns.nextdns.io/aaaaaa" \
	"сверочный URL обновлён на актуальный"
assert_eq "1" "$(grep -c '^applied' "$DOH_STATE")" \
	"строка applied одна, а не растёт с каждым захватом"

# --- Возврат ------------------------------------------------------------------

: > "$TT_CALLS"
doh_takeover_release

assert_eq "https://cloudflare-dns.com/dns-query" "$(url_of cfg01)" \
	"первому инстансу возвращён его резолвер"
assert_eq "https://dns.google/dns-query" "$(url_of cfg02)" \
	"второму инстансу возвращён его резолвер"
assert_contains "$(calls)" "doh-init restart" "сервис перезапущен с прежними настройками"
assert_eq "" "$(state_lines)" "состояние удалено"

# Возврат без состояния — не ошибка: stop_service вызывается и когда захвата
# не было вовсе.
: > "$TT_CALLS"
assert_exit 0 "возврат без состояния молчит и не падает" doh_takeover_release
assert_eq "" "$(calls)" "и ничего не дёргает"

# --- Чужая правка -------------------------------------------------------------
# Пользователь мог сменить resolver_url руками, пока мы владели. Наш бэкап на
# этот момент устарел, и восстановить его значило бы затереть осознанную чужую
# правку.

reset_all
TT_DOH_RUNNING=1 doh_takeover_apply
uci set "https-dns-proxy.cfg01.resolver_url=https://dns.quad9.net/dns-query"
: > "$TT_CALLS"
doh_takeover_release

assert_eq "https://dns.quad9.net/dns-query" "$(url_of cfg01)" \
	"чужая правка не затёрта нашим бэкапом"
assert_contains "$(calls)" "logger" "о ней сказано в журнал"
assert_eq "" "$(state_lines)" "состояние всё равно выброшено"

# --- Изменился состав секций --------------------------------------------------
# Секции адресуются индексами — реальных имён анонимных секций uci не печатает,
# — поэтому удалённый инстанс опаснее изменённого значения: уцелевший всё ещё
# держит наш URL, сверка значений молчит, а восстановление по индексу записало
# бы в него резолвер удалённого соседа.

reset_all
TT_DOH_RUNNING=1 doh_takeover_apply
uci delete https-dns-proxy.cfg01
: > "$TT_CALLS"
doh_takeover_release

assert_eq "https://dns.nextdns.io/66db2b" "$(url_of cfg02)" \
	"состав секций изменился — чужой конфиг не тронут"
assert_contains "$(calls)" "logger" "и об этом сказано в журнал"
assert_eq "" "$(state_lines)" "состояние выброшено"

# --- Сервис не был запущен до нас --------------------------------------------

reset_all
TT_DOH_RUNNING=0 doh_takeover_apply
assert_contains "$(calls)" "doh-init start" "неработавший сервис поднят, а не перезапущен"
assert_contains "$(state_lines)" "running 0" "запомнили, что сервис не работал"

: > "$TT_CALLS"
doh_takeover_release
assert_contains "$(calls)" "doh-init stop" "и при возврате он погашен, а не перезапущен"

# --- Инстансов нет вовсе ------------------------------------------------------

reset_all
: > "$TT_UCI_DB"
TT_DOH_RUNNING=0 doh_takeover_apply

_created=$(awk -F'\t' '$1 == "created" { print $2 }' "$DOH_STATE")
# Именно индекс, а НЕ имя, которое напечатал `uci add`: то имя внутреннее для
# процесса, в файле конфига не сохраняется, и при возврате — уже в другом
# процессе — не привязано ни к чему.
assert_eq "@https-dns-proxy[0]" "$_created" \
	"созданная секция запомнена индексом, а не именем из uci add"
assert_eq "https://dns.nextdns.io/66db2b" "$(url_of "$_created")" \
	"созданный инстанс сразу на нашем резолвере"
assert_eq "5053" "$(uci -q get "https-dns-proxy.$_created.listen_port")" \
	"порт задан, иначе их init не поднимет инстанс"

: > "$TT_CALLS"
doh_takeover_release
assert_eq "" "$(url_of "$_created")" "созданный нами инстанс при возврате удалён"

# --- Отказы -------------------------------------------------------------------

reset_all 1 selective doh ''
assert_exit 1 "без URL захвата нет" doh_takeover_apply
assert_eq "" "$(state_lines)" "и состояние не создано"
assert_contains "$(calls)" "logger" "причина ушла в журнал"

reset_all
# Подменяется DOH_BIN, а не TT_DOH_BIN: init-скрипт разрешает переопределение
# один раз при подключении, и правка переменной окружения после этого уже ни на
# что не влияет.
_doh_bin_saved="$DOH_BIN"
DOH_BIN="$sandbox/nope"
assert_exit 1 "без бинарника прокси захвата нет" doh_takeover_apply
assert_eq "" "$(state_lines)" "и состояние не создано"
DOH_BIN="$_doh_bin_saved"

# --- Пропуск возврата при рестарте -------------------------------------------
# Между stop и start настройки те же, и отдавать DNS сети обратно, чтобы через
# секунду забрать снова, значит два лишних рестарта dnsmasq и провал DNS в
# промежутке. Ровно по этой причине там же пропускается unlink_dnsmasq.

reset_all
TT_DOH_RUNNING=1 doh_takeover_apply
unlink_dnsmasq() { :; }
: > "$TT_CALLS"
_TT_RESTARTING=1 stop_service
assert_eq "https://dns.nextdns.io/66db2b" "$(url_of cfg01)" \
	"при рестарте владение не отдаётся"
assert_contains "$(state_lines)" "applied" "состояние живо"

: > "$TT_CALLS"
_TT_RESTARTING=0 stop_service
assert_eq "https://cloudflare-dns.com/dns-query" "$(url_of cfg01)" \
	"обычный стоп владение отдаёт"

# --- Прерванный рестарт -------------------------------------------------------
# stop освобождение пропустил, а start до него не дошёл: служба выключена,
# клиента нет. Без возврата здесь DNS сети остался бы нашим при неработающей
# службе — ровно то, что выбранный жизненный цикл запрещает. Тот же довод, по
# которому здесь уже разбирается маршрутизация.

reset_all
TT_DOH_RUNNING=1 doh_takeover_apply
: > "$TT_CALLS"
_TT_RESTARTING=1 abort_restart_cleanup
assert_eq "https://cloudflare-dns.com/dns-query" "$(url_of cfg01)" \
	"прерванный рестарт возвращает владение"
assert_eq "" "$(state_lines)" "состояние удалено"

tt_test_summary
