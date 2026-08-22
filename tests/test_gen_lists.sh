#!/bin/sh
. "$(dirname "$0")/lib.sh"

GEN=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/gen-lists
LISTS=tests/fixtures/lists

# Записи для селективного режима: два списка, подсети, свой URL и свои домены.
cat > "$TT_TEST_TMP/sel.tsv" <<'EOFDATA'
main.mode	selective
network.tunnel_list_dns	1
network.list_resolver	1.1.1.1
lists.source	Russia/inside-raw.lst
lists.source	Services/youtube.lst
lists.subnet	Subnets/IPv4/telegram.lst
lists.subnet	Subnets/IPv6/telegram.lst
lists.url	https://example.org/my.lst
domains.bypass	extra.example
domains.direct	bank.example
EOFDATA

out="$TT_TEST_TMP/out"
mkdir -p "$out"
summary="$(sh "$GEN" "$TT_TEST_TMP/sel.tsv" "$LISTS" "$out")"
dnsmasq="$(cat "$out/dnsmasq.conf")"
elements="$(cat "$out/elements.nft")"

assert_contains "$dnsmasq" 'nftset=/youtube.com/4#inet#trusttunnel#tt_bypass4' "emits ipv4 nftset line"
assert_contains "$dnsmasq" 'nftset=/youtube.com/6#inet#trusttunnel#tt_bypass6' "emits ipv6 nftset line"
assert_contains "$dnsmasq" 'server=/youtube.com/1.1.1.1' "emits per-domain resolver"
assert_contains "$dnsmasq" 'nftset=/ua/4#inet#trusttunnel#tt_bypass4' "normalizes .ua to ua"
assert_contains "$dnsmasq" 'nftset=/blocked.example/4#inet#trusttunnel#tt_bypass4' "lowercases"
assert_contains "$dnsmasq" 'nftset=/extra.example/4#inet#trusttunnel#tt_bypass4' "includes user bypass domains"
assert_contains "$dnsmasq" 'nftset=/mysite.example/4#inet#trusttunnel#tt_bypass4' "includes custom url list"

# bank.example в direct — он и его поддомен обязаны исчезнуть.
assert_eq "0" "$(printf '%s\n' "$dnsmasq" | grep -c 'bank\.example')" "direct domains are subtracted with subdomains"
# example.com встречается в двух списках — строка должна быть одна.
assert_eq "1" "$(printf '%s\n' "$dnsmasq" | grep -c 'nftset=/example\.com/4#')" "deduplicates across sources"

assert_contains "$elements" 'add element inet trusttunnel tt_bypass4 { 149.154.160.0/20 }' "ipv4 cidr element"
assert_contains "$elements" 'add element inet trusttunnel tt_bypass6 { 2001:67c:4e8::/48 }' "ipv6 cidr element"
assert_contains "$elements" 'add element inet trusttunnel tt_bypass4 { 1.1.1.1 }' "resolver is routed into the tunnel"

# Источники дают 9 уникальных доменов (ua, example.com, blocked.example,
# bank.example, sub.bank.example, youtube.com, ytimg.com, mysite.example,
# extra.example), из них 1.2.3.4 отброшен, а bank.example с поддоменом снят
# списком direct — остаётся 7.
assert_contains "$summary" "domains 7" "summary counts domains"
assert_contains "$summary" "cidr4 2" "summary counts ipv4 cidrs"
assert_contains "$summary" "cidr6 1" "summary counts ipv6 cidrs"
assert_contains "$summary" "dropped 1" "summary counts rejected entries"
assert_contains "$summary" "subtracted 2" "summary counts entries removed by the direct list"

# Свои домены выкладываются отдельным файлом: их прогревает warm-sets сразу
# после применения настроек, потому что своё устройство человека обычно уже
# держит адрес в кэше и роутер не спрашивает вовсе. В файл идут ТОЛЬКО свои
# домены — тысяча с лишним доменов из списков сообщества так не прогревается.
own="$(cat "$out/own.domains")"
assert_eq "extra.example" "$own" "own domains are published for warm-up"
assert_contains "$summary" "own 1" "summary counts own domains"

# «Не обходить» вычитается и здесь: прогревать домен, которого нет в
# dnsmasq.conf, значило бы наполнять набор адресами, для которых обхода нет.
cat > "$TT_TEST_TMP/ownsub.tsv" <<'EOFDATA'
main.mode	selective
domains.bypass	keep.example
domains.bypass	skip.example
domains.bypass	sub.skip.example
domains.direct	skip.example
EOFDATA
outo="$TT_TEST_TMP/out-own"; mkdir -p "$outo"
sh "$GEN" "$TT_TEST_TMP/ownsub.tsv" "$LISTS" "$outo" >/dev/null
assert_eq "keep.example" "$(cat "$outo/own.domains")" 	"own domains drop what the direct list excludes, subdomains included"

# tunnel_list_dns=0: ни server=, ни адреса резолвера в сете.
sed 's/^network.tunnel_list_dns\t1$/network.tunnel_list_dns\t0/' "$TT_TEST_TMP/sel.tsv" > "$TT_TEST_TMP/nodns.tsv"
out2="$TT_TEST_TMP/out2"; mkdir -p "$out2"
sh "$GEN" "$TT_TEST_TMP/nodns.tsv" "$LISTS" "$out2" >/dev/null
assert_eq "0" "$(grep -c '^server=' "$out2/dnsmasq.conf")" "no per-domain resolver when disabled"
assert_eq "0" "$(grep -c '1\.1\.1\.1' "$out2/elements.nft")" "no resolver element when disabled"

# Два файла подсетей одного семейства должны СЛОЖИТЬСЯ, а не заменить друг
# друга. Основной набор фикстур держит по одному файлу на семейство, поэтому
# ошибка обрезания файла в цикле для него невидима — этот случай её и ловит.
cat > "$TT_TEST_TMP/two.tsv" <<'EOF'
main.mode	selective
network.tunnel_list_dns	0
lists.subnet	Subnets/IPv4/telegram.lst
lists.subnet	Subnets/IPv4/discord.lst
EOF
out4="$TT_TEST_TMP/out4"; mkdir -p "$out4"
sum4="$(sh "$GEN" "$TT_TEST_TMP/two.tsv" "$LISTS" "$out4")"
el4="$(cat "$out4/elements.nft")"
assert_contains "$el4" "149.154.160.0/20" "keeps CIDRs from the first subnet list"
assert_contains "$el4" "162.159.128.0/19" "keeps CIDRs from the second subnet list"
assert_contains "$sum4" "cidr4 3" "counts CIDRs from every same-family subnet list"

# Пустой список прямых исключений (по умолчанию в конфигурации) не должен
# в результате awk NR == FNR идиомы съедать все домены. Проверяем что с пустым
# domains.direct все 9 уникальных нормализованных доменов выживают.
cat > "$TT_TEST_TMP/nodir.tsv" <<'EOF'
main.mode	selective
network.tunnel_list_dns	1
network.list_resolver	1.1.1.1
lists.source	Russia/inside-raw.lst
lists.source	Services/youtube.lst
lists.url	https://example.org/my.lst
domains.bypass	extra.example
EOF
out5="$TT_TEST_TMP/out5"; mkdir -p "$out5"
sum5="$(sh "$GEN" "$TT_TEST_TMP/nodir.tsv" "$LISTS" "$out5")"
dns5="$(cat "$out5/dnsmasq.conf")"
assert_contains "$sum5" "subtracted 0" "empty direct list subtracts nothing"
assert_contains "$sum5" "domains 9" "empty direct list keeps all domains"
assert_contains "$dns5" 'nftset=/bank.example/4#inet#trusttunnel#tt_bypass4' "bank.example present when not excluded"

# В режиме full генератор вызываться не должен.
printf 'main.mode\tfull\n' > "$TT_TEST_TMP/full.tsv"
out3="$TT_TEST_TMP/out3"; mkdir -p "$out3"
assert_exit 1 "refuses to run in full mode" sh "$GEN" "$TT_TEST_TMP/full.tsv" "$LISTS" "$out3"


# --- Три режима резолвинга доменов из списков --------------------------------
#
# Прежде это была пара «флаг tunnel_list_dns + адрес», и они могли
# противоречить друг другу. Теперь одно поле list_dns с тремя значениями.
# Проверяется каждое, потому что от режима зависят СРАЗУ ДВА файла: строка
# server= в конфиге dnsmasq и наличие адреса резолвера в наборе обхода.

# Заглушка «прокси установлен». Она обязательна для всех проверок режима doh:
# без неё генератор откатывается к провайдеру, и проверки проходили бы по
# неверной причине. Путь берётся из окружения именно для этого.
stub_doh="$TT_TEST_TMP/https-dns-proxy"
printf '#!/bin/sh\nexit 0\n' > "$stub_doh"
chmod +x "$stub_doh"

# plain: обычный DNS на указанный адрес, и этот адрес обязан попасть в набор —
# именно так запрос уходит внутри туннеля.
sed 's/^network.tunnel_list_dns\t1$/network.list_dns\tplain/' "$TT_TEST_TMP/sel.tsv" > "$TT_TEST_TMP/plain.tsv"
outp="$TT_TEST_TMP/out-plain"; mkdir -p "$outp"
sh "$GEN" "$TT_TEST_TMP/plain.tsv" "$LISTS" "$outp" >/dev/null
assert_contains "$(cat "$outp/dnsmasq.conf")" 'server=/youtube.com/1.1.1.1' "plain: per-domain resolver"
assert_contains "$(cat "$outp/elements.nft")" 'tt_bypass4 { 1.1.1.1 }' "plain: resolver goes into the bypass set"

# doh: запрос уходит на локальный прокси, и в наборе резолвера быть НЕ должно —
# шифрованный запрос идёт напрямую, а не через туннель.
sed 's/^network.tunnel_list_dns\t1$/network.list_dns\tdoh/' "$TT_TEST_TMP/sel.tsv" > "$TT_TEST_TMP/doh.tsv"
{
	printf 'network.list_doh_url\thttps://dns.example/dns-query\n'
	printf 'network.list_doh_port\t5460\n'
} >> "$TT_TEST_TMP/doh.tsv"
outd="$TT_TEST_TMP/out-doh"; mkdir -p "$outd"
TT_DOH_BIN="$stub_doh" sh "$GEN" "$TT_TEST_TMP/doh.tsv" "$LISTS" "$outd" >/dev/null
assert_contains "$(cat "$outd/dnsmasq.conf")" 'server=/youtube.com/127.0.0.1#5460' "doh: resolver is the local proxy"
assert_eq "0" "$(grep -c '127.0.0.1' "$outd/elements.nft")" "doh: nothing added to the bypass set"

# Порт берётся из настройки, а не зашит: иначе конфликт с другим прокси на
# роутере было бы нечем разрешить.
sed 's/^network.list_doh_port\t5460$/network.list_doh_port\t5999/' "$TT_TEST_TMP/doh.tsv" > "$TT_TEST_TMP/doh2.tsv"
outd2="$TT_TEST_TMP/out-doh2"; mkdir -p "$outd2"
TT_DOH_BIN="$stub_doh" sh "$GEN" "$TT_TEST_TMP/doh2.tsv" "$LISTS" "$outd2" >/dev/null
assert_contains "$(cat "$outd2/dnsmasq.conf")" 'server=/youtube.com/127.0.0.1#5999' "doh: port comes from the setting"

# Главная защита: DoH выбран, но прокси НЕ установлен. Направлять dnsmasq в
# порт, где никто не слушает, нельзя — домены из списков перестали бы
# резолвиться молча. Ожидается откат к провайдеру и внятное предупреждение.
outn="$TT_TEST_TMP/out-doh-nobin"; mkdir -p "$outn"
warn=$(TT_DOH_BIN="$TT_TEST_TMP/nope" sh "$GEN" "$TT_TEST_TMP/doh.tsv" "$LISTS" "$outn" 2>&1 >/dev/null)
assert_eq "0" "$(grep -c '^server=' "$outn/dnsmasq.conf")" "doh without the proxy: no resolver line at all"
assert_contains "$warn" "install https-dns-proxy" "doh without the proxy: says what to install"
assert_contains "$(cat "$outn/dnsmasq.conf")" 'nftset=/youtube.com/4' "doh without the proxy: bypass still works"

# DoH выбран, прокси есть, но адрес не задан — тот же откат, другая причина.
grep -v '^network.list_doh_url' "$TT_TEST_TMP/doh.tsv" > "$TT_TEST_TMP/doh-nourl.tsv"
outu="$TT_TEST_TMP/out-doh-nourl"; mkdir -p "$outu"
warn2=$(TT_DOH_BIN="$stub_doh" sh "$GEN" "$TT_TEST_TMP/doh-nourl.tsv" "$LISTS" "$outu" 2>&1 >/dev/null)
assert_eq "0" "$(grep -c '^server=' "$outu/dnsmasq.conf")" "doh without a URL: no resolver line"
assert_contains "$warn2" "no resolver URL" "doh without a URL: says what is missing"

# provider: своего резолвера не задаём вовсе.
sed 's/^network.tunnel_list_dns\t1$/network.list_dns\tprovider/' "$TT_TEST_TMP/sel.tsv" > "$TT_TEST_TMP/prov.tsv"
outv="$TT_TEST_TMP/out-provider"; mkdir -p "$outv"
sh "$GEN" "$TT_TEST_TMP/prov.tsv" "$LISTS" "$outv" >/dev/null
assert_eq "0" "$(grep -c '^server=' "$outv/dnsmasq.conf")" "provider: no per-domain resolver"
assert_eq "0" "$(grep -c '1.1.1.1' "$outv/elements.nft")" "provider: nothing added to the bypass set"

# Совместимость: на роутере, обновлённом с прежней версии, list_dns может
# отсутствовать. Тогда решает старый флаг — иначе обновление молча сменило бы
# поведение резолвинга.
assert_contains "$dnsmasq" 'server=/youtube.com/1.1.1.1' "legacy flag still selects plain behaviour"

tt_test_summary
