#!/bin/sh
. "$(dirname "$0")/lib.sh"

GEN=packages/luci-app-trusttunnel/root/usr/libexec/trusttunnel/gen-config
MIN=tests/fixtures/records/minimal.tsv
FULL=tests/fixtures/records/full.tsv

out_min="$(sh "$GEN" "$MIN")"
out_full="$(sh "$GEN" "$FULL" tests/fixtures/exclusions-extra.txt)"

# Значения, обязательные для роутера и не настраиваемые пользователем.
assert_contains "$out_min" 'vpn_mode = "general"' "vpn_mode is always general"
assert_contains "$out_min" 'killswitch_enabled = false' "client killswitch is off"
# device_name и use_existing НЕ генерируются намеренно. С клиента 1.0.62 эти
# ключи в схеме есть, но пакет ими не пользуется: устройство создаёт клиент,
# а маршрут привязывается к нему после старта (routing attach) — так работает
# и на клиентах старше 1.0.62, которые ключи молча игнорируют. Раньше ключи
# генерировались в расчёте на то, что клиент возьмёт наше устройство; он
# игнорировал их и создавал своё, а наше оставалось без носителя.
assert_eq "0" "$(printf '%s' "$out_min" | grep -c 'use_existing')" "no use_existing key"
assert_eq "0" "$(printf '%s' "$out_min" | grep -c 'device_name')" "no device_name key"
assert_contains "$out_min" 'included_routes = []' "client does not manage routes"
assert_contains "$out_min" 'change_system_dns = false' "does not touch system dns"
assert_contains "$out_min" 'mtu_size = 1350' "mtu reaches the client, which owns the device"

assert_contains "$out_min" 'hostname = "vpn.example.com"' "endpoint hostname"
assert_contains "$out_min" 'addresses = ["1.2.3.4:443"]' "single address as array"
assert_contains "$out_min" 'username = "alice"' "username"
assert_contains "$out_min" 'password = "s3cret"' "password"
assert_contains "$out_min" 'mtu_size = 1350' "mtu is a bare number"
assert_contains "$out_min" 'loglevel = "info"' "default log level"
assert_contains "$out_min" 'exclusions = []' "no exclusions by default"
assert_contains "$out_min" 'upstream_protocol = "http2"' "default protocol"
assert_contains "$out_min" 'anti_dpi = false' "anti_dpi defaults off"
assert_contains "$out_min" 'post_quantum_group_enabled = true' "post quantum defaults on"
assert_contains "$out_min" 'has_ipv6 = true' "has_ipv6 defaults on"
assert_contains "$out_min" 'dns_upstreams = []' "no dns upstreams by default"
assert_contains "$out_min" 'custom_sni = ""' "custom_sni empty by default"
assert_contains "$out_min" 'client_random = ""' "client_random empty by default"

# Настройки исключений и буферов клиента (появились в клиенте 1.0.63 и 1.1.5).
# Дефолты совпадают с дефолтами клиента, кроме early-ack: вендор рекомендует
# его, когда DNS резолвит не клиент (у нас — роутер) и для wildcard-исключений.
assert_contains "$out_min" 'exclusions_tcp_early_ack_enabled = true' "early ack defaults on"
assert_contains "$out_min" 'exclusions_preresolve_enabled = true' "preresolve defaults on"
assert_contains "$out_min" 'exclusions_preresolve_max_queries = 50' "preresolve limit defaults to 50"
assert_contains "$out_min" 'exclusions_scannable_ports = "443,80,8080,8008,853"' "scannable ports default list"
assert_contains "$out_min" 'tcp_recv_buf_size = 0' "tcp recv buffer defaults to client default"
assert_contains "$out_min" 'tcp_send_buf_size = 0' "tcp send buffer defaults to client default"

assert_contains "$out_full" 'addresses = ["1.2.3.4:443", "[2001:db8::1]:443"]' "multiple addresses"
assert_contains "$out_full" 'loglevel = "debug"' "log level from config"
assert_contains "$out_full" 'upstream_protocol = "http3"' "http3 protocol"
assert_contains "$out_full" 'anti_dpi = true' "anti_dpi on"
assert_contains "$out_full" 'post_quantum_group_enabled = false' "post quantum off"
assert_contains "$out_full" 'skip_verification = true' "skip verification on"
assert_contains "$out_full" 'has_ipv6 = false' "has_ipv6 off"
assert_contains "$out_full" 'mtu_size = 1400' "mtu from config"
assert_contains "$out_full" 'dns_upstreams = ["tls://1.1.1.1", "quic://dns.adguard.com:8853"]' "dns upstreams array"
assert_contains "$out_full" 'custom_sni = "cdn.example.net"' "custom_sni from config"
assert_contains "$out_full" 'client_random = "a1b2c3d4/ffffffff"' "client_random from config"
assert_contains "$out_full" 'exclusions_tcp_early_ack_enabled = false' "early ack can be turned off"
assert_contains "$out_full" 'exclusions_preresolve_enabled = false' "preresolve can be turned off"
assert_contains "$out_full" 'exclusions_preresolve_max_queries = 10' "preresolve limit from config"
assert_contains "$out_full" 'exclusions_scannable_ports = "443,8443:8450"' "scannable ports from config"
assert_contains "$out_full" 'tcp_recv_buf_size = 131072' "tcp recv buffer from config"
assert_contains "$out_full" 'tcp_send_buf_size = 65536' "tcp send buffer from config"

# Числовые ключи идут в TOML голыми числами: мусор вместо числа сломал бы
# разбор конфига, и клиент не стартовал бы вовсе. Поэтому не-число
# заменяется значением по умолчанию.
tab=$(printf '\t')
sed -e "s/^network.preresolve_max${tab}.*/network.preresolve_max${tab}abc/" \
    -e "s/^network.tcp_recv_buf${tab}.*/network.tcp_recv_buf${tab}-5/" \
    "$FULL" > "$TT_TEST_TMP/junk.tsv"
out_junk="$(sh "$GEN" "$TT_TEST_TMP/junk.tsv")"
assert_contains "$out_junk" 'exclusions_preresolve_max_queries = 50' "non-numeric preresolve limit falls back to default"
assert_contains "$out_junk" 'tcp_recv_buf_size = 0' "negative tcp buffer falls back to default"
assert_contains "$out_full" 'password = "pa\"ss\\with"' "escapes quotes and backslashes"

assert_contains "$out_full" 'exclusions = ["bank.example", "*.local.example", "listed-one.example", "listed-two.example"]' \
	"direct domains plus extra exclusions"

# Сертификат приходит третьим аргументом как файл, а не через records:
# в records значение не может содержать перевод строки, а PEM многострочный.
printf -- '-----BEGIN CERTIFICATE-----\nMIIBdummy\n-----END CERTIFICATE-----\n' \
	> "$TT_TEST_TMP/cert.pem"
out_cert="$(sh "$GEN" "$MIN" "" "$TT_TEST_TMP/cert.pem")"
assert_contains "$out_cert" "certificate = '''" "emits a multi-line literal for a PEM"
assert_contains "$out_cert" "-----END CERTIFICATE-----" "PEM body is copied verbatim"
assert_contains "$out_min" 'certificate = ""' "empty certificate when no PEM file is given"

# Валидация обязательных полей.
printf 'main.mode\tselective\n' > "$TT_TEST_TMP/bare.tsv"
assert_exit 1 "fails without endpoint credentials" sh "$GEN" "$TT_TEST_TMP/bare.tsv"

tt_test_summary
