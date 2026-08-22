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
assert_contains "$out_min" 'exclusions_tcp_early_ack_enabled = true' "early ack is on"
# device_name и use_existing больше НЕ генерируются: таких ключей в схеме
# клиента не существует, он их молча игнорировал и создавал своё устройство,
# а созданное нами оставалось без носителя — помеченный трафик отбрасывался.
# Проверяется обратное: что выдуманных ключей в конфиге не осталось.
assert_eq "0" "$(printf '%s' "$out_min" | grep -c 'use_existing')" "no invented use_existing key"
assert_eq "0" "$(printf '%s' "$out_min" | grep -c 'device_name')" "no invented device_name key"
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

assert_contains "$out_full" 'addresses = ["1.2.3.4:443", "[2001:db8::1]:443"]' "multiple addresses"
assert_contains "$out_full" 'loglevel = "debug"' "log level from config"
assert_contains "$out_full" 'upstream_protocol = "http3"' "http3 protocol"
assert_contains "$out_full" 'anti_dpi = true' "anti_dpi on"
assert_contains "$out_full" 'post_quantum_group_enabled = false' "post quantum off"
assert_contains "$out_full" 'skip_verification = true' "skip verification on"
assert_contains "$out_full" 'has_ipv6 = false' "has_ipv6 off"
assert_contains "$out_full" 'mtu_size = 1400' "mtu from config"
assert_contains "$out_full" 'dns_upstreams = ["tls://1.1.1.1", "quic://dns.adguard.com:8853"]' "dns upstreams array"
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
