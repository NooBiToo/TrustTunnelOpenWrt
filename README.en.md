# luci-app-trusttunnel

*[Русская версия](README.md)*

A [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) client for
OpenWrt 25.12+ with selective bypass by domain lists, configuration and
diagnostics in the LuCI web interface.

TrustTunnel is an open VPN protocol originally developed by AdGuard VPN. Its
traffic is indistinguishable from ordinary HTTPS, which lets it pass through
DPI. This package runs the client on your router and answers the main
question of home use: **which** traffic goes through the tunnel, and which
stays direct.

---

## Contents

- [What the package does](#what-the-package-does)
- [Installation](#installation)
- [Configuring through the interface](#configuring-through-the-interface)
- [Two modes](#two-modes)
- [How it works internally](#how-it-works-internally)
- [Configuring without the interface](#configuring-without-the-interface)
- [Full settings reference](#full-settings-reference) — the short table; every option explained at length in [SETTINGS.ru.md](SETTINGS.ru.md) (in Russian)
- [Diagnostics](#diagnostics)
- [Limitations](#limitations)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Donate](#donate)
- [License and acknowledgements](#license-and-acknowledgements)

---

## What the package does

1. **Runs the TrustTunnel client as a system service.** The client starts
   under procd with auto-restart, waits for the network and clock sync to be
   ready, and logs to the system journal.

2. **Integrates community bypass lists.** The
   [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains)
   catalog is pulled straight from GitHub; files are selected with
   checkboxes: regional lists (Russia), categories (anime, block,
   geoblock, hodca, news, porn), individual services (YouTube, Telegram,
   Discord, Meta, TikTok and others), and CIDR subnets for several services.
   New files that appear in the upstream repository show up in the interface
   on their own, without a package update.

3. **Accepts your own domains.** Two independent lists: "bypass" — added on
   top of the selected community lists, and "do not bypass" — always sent
   out directly, and takes priority over everything else.

4. **Moves configuration into the interface.** The server is set up either
   by importing the config your server generated, or by filling in the
   fields by hand. No hand-editing of TOML.

5. **Gives you diagnostics.** Ping each endpoint address with numbers,
   compare the external IP through the tunnel and directly, and check a
   specific domain: enter `youtube.com` and get back which list it matched,
   which addresses it resolves to, whether they landed in the nftables set,
   and whether it will go through the tunnel.

---

## Installation

One command on the router:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/NooBiToo/TrustTunnelOpenWrt/main/install.sh)"
```

What the script does:

1. Checks that this is OpenWrt 25.12 or newer and that `apk` is available.
2. Installs dependencies: `kmod-tun`, `ip-full`, `curl`, `ca-bundle`, `ucode-mod-math`. None of
   these ship with a stock image: without `kmod-tun`, `/dev/net/tun` does
   not even exist, and busybox's `ip` has no `tuntap` subcommand at all —
   the one used to bring the tunnel device up.
3. Checks `dnsmasq` for `nftset` support and, if missing, asks for
   confirmation before installing `dnsmasq-full`.
4. Downloads `luci-app-trusttunnel-*.apk` from the latest release and
   installs it.
5. Detects the architecture and installs the client binary with
   TrustTunnel's own installer script into `/opt/trusttunnel_client`.
6. Restarts `rpcd` so LuCI picks up the new backend.

The script is idempotent: running it again updates the package and the
binary without touching your settings, and stops the running service before
replacing the binary.

The service is **disabled** right after installation, on purpose:
configure first, start second.

### About dnsmasq and dnsmasq-full

Verified on a real OpenWrt 25.12.5 router: the stock `dnsmasq` is built
**without** `nftset` support — `dnsmasq --test` on an `nftset=` line answers
`recompile with HAVE_NFTSET defined`. Without `dnsmasq-full`, the "bypass by
list" mode (the default) does not work at all: dnsmasq cannot put resolved
addresses into the nftables set, so the bypass set stays empty no matter
what lists you pick. That is why the installer defaults to offering
`dnsmasq-full`.

Installing `dnsmasq-full` replaces the system `dnsmasq` package and
**restarts DNS on the router** — LAN clients' DNS queries go unanswered for
a few seconds. That is why the replacement only happens after you confirm
it. Decline, and only "everything through VPN" mode will work.

### Which routers are supported

The package itself is architecture-independent: it contains only shell scripts,
ucode, JS and config files, so the same `.apk` installs on any platform — it is
marked `noarch`. There are no per-architecture builds, and none are needed.

The limit comes from the **client binary**, which the package does not contain
but downloads with the vendor installer. TrustTunnel ships prebuilt binaries
for:

| CPU (`uname -m`) | Typical routers |
|---|---|
| `aarch64` | nearly all current consumer models: Xiaomi, Keenetic, GL.iNet, mid and high-range Asus |
| `armv7l` | the previous generation of the same class, some Zyxel and Netgear |
| `mipsel` | mass-market budget models on ath79 and ramips: TP-Link, D-Link, Netis |
| `mips` | the same family, big-endian |
| `x86_64` | mini PCs, virtual machines, self-built gateways |

Together these cover the vast majority of devices OpenWrt gets installed on.

**Not supported:** ARMv5 and ARMv6 (older models such as some `arm926ej-s` and
`xscale` targets), `mips64`, `riscv64`, `powerpc`. No client binary exists for
them.

The check runs **before** anything is installed, and against `uname -m` — the
same identifier the vendor installer uses to pick a build. It used to compare
OpenWrt's package architecture name instead, which produced a false pass:
OpenWrt's `arm_*` targets include ARMv5 and ARMv6, where `uname -m` reports
`armv5tel` or `armv6l`. Such a router passed the check, the package installed,
and the failure arrived from the vendor afterwards — leaving a menu entry and a
service with no client behind it.


---

## Configuring through the interface

Open **Services → TrustTunnel**. Three pages: "Status", "Settings" and
"Diagnostics". Every setting lives on one page behind tabs that switch
instantly, with no page reload.

Setup order, top to bottom through the **Settings** tabs:

1. **Server** — press **Import…** and paste the config your TrustTunnel server
   generated, or fill in the address, TLS host name, user and password by hand.
2. **Lists** — check the community lists you need and add your own list URLs if
   you have any.
3. **My domains** — if needed, add domains to always bypass or always keep
   direct.
4. **General** — turn on **Start on boot**, press **Save & Apply**, then press
   **Start** on the Status page.

The **Network** tab is rarely needed: MTU and the routing internals live there.

### Settings

Both forms a server hands out are accepted: the configuration file text, and a
`tt://` deep link. They are told apart automatically, because `setup_wizard`
takes them through different, mutually exclusive flags — feeding a link in as
if it were a file makes it fail to parse outright.

The fast path is **Import endpoint configuration**: paste the configuration
text your TrustTunnel server generated, and the fields fill themselves in.
Parsing is done by the client own `setup_wizard` utility, so exactly the
formats TrustTunnel itself understands are supported.

Filled in by hand:

- **Hostname** — used for the TLS session, not for routing.
- **Addresses** — `host:port` or `[ipv6]:port`. Several can be listed: the
  client pings them and picks the fastest.
- **Username** and **Password**.

Everything else has sane defaults. Change these deliberately:

- **Transport** — HTTP/2 or HTTP/3 (QUIC). QUIC is often faster, but some
  networks throttle or block UDP.
- **Anti-DPI** — enables deep-packet-inspection countermeasures.
- **Post-quantum key exchange** — on by default.
- **Skip certificate verification** — accepts any certificate. Only for a
  self-signed setup you control.
- **Pinned certificate (PEM)** — paste the server certificate here if it is
  self-signed. Then the system trust store is not needed.

### Lists

Checkboxes for allow-domains files, grouped by section, with each file's
size. The catalog comes from the GitHub API and is cached for a day; the
**Refresh catalog** button clears the cache.

Below that is the **Extra list URLs** field: any URL returning one domain
per line. Downloaded alongside the community lists.

**Download lists now** runs the download and regenerates the rules
immediately. Otherwise, a cron job refreshes the lists daily at 04:17. The
**Update automatically** checkbox only disables the schedule — the button
still always works.

### My domains

Two fields.

**Bypass these** — these domains go through the tunnel in addition to the
selected lists. Subdomains are matched automatically: an entry for
`example.com` also covers `www.example.com` — that is how domain matching
works in dnsmasq, and for the same reason an entry for a bare TLD (say,
`ua`) covers that whole zone.

**Do not bypass these** — always sent out directly, and **takes priority
over everything else**. This holds even when the domain is in a selected
community list, and even when its IP address is shared with a bypassed
domain (typical for a CDN): the exclusion is applied by the client itself,
by SNI, after the kernel has already marked the packet. Accepts a domain,
`*.domain`, an IP address, or a CIDR range.

Domains with non-ASCII characters are rejected during normalization — use
punycode (`xn--…`). The number of rejected entries is shown in the
interface.

### Status and test

Shows the state of the service, the tunnel device, routing and the nft
table, the size of the bypass set, the number of domains in the lists, and
the time of the last update.

Three diagnostic tools:

- **Ping the endpoint** — per address: loss and min/avg/max.
- **Compare external IP** — shows the external address through the tunnel
  and directly, side by side. If they match, no traffic is going through
  the tunnel.
- **Check a domain** — the tool to reach for when "it doesn't work". Enter a
  domain and get back: the normalized name, which selected lists it matched,
  which addresses it resolves to, whether they landed in the bypass set, and
  a verdict with the reason behind it.

A tail of the client log is shown at the bottom.

---

### The Diagnostics tab

A tab of its own that walks the whole chain in one go and returns a list: what
was checked, the verdict, and — where something is wrong — what to do about it.
It runs on opening the page; the **Check again** button is for a repeat run
after you have fixed something. The checks are ordered the way the package actually works, so read
top to bottom and look for the first place where things diverge.

| Group | What is checked |
|---|---|
| Configuration | endpoint address, credentials, TLS host name, mode, selected lists |
| Prerequisites | client binary, `nftset` support in dnsmasq, `/dev/net/tun` |
| Service | enabled on boot, running right now |
| Kernel state | device and its MTU, tunnel carrier, routing rule and table, nftables table, firewall zone, bypass set size |
| Lists | domain count, last update, whether the dnsmasq config is published |
| Network | endpoint reachability, whether traffic actually uses the tunnel |

The verdicts distinguish four states, and the distinction matters more than it
looks:

- **ok** — checked and working;
- **check** — works, with a remark; for instance the tunnel is configured but
  has no carrier because the client has not connected yet;
- **problem** — not working, with the fix written next to it;
- **skipped** — nothing to check because an earlier link is not ready. A skip
  is deliberately not shown as a failure: with the service stopped, the kernel
  checks must not go red.

Note the difference between the **device** and the **tunnel carrier**. The
device is created by the client, and if it exists with the right MTU and the
route is attached to it, then our side is done. Carrier only appears once the client has
attached and the tunnel is established. Device fine but no carrier means the
cause is in the client log, not in the routing.

### Versions

The bottom of the status page shows the installed package version and the
TrustTunnel client version, each with its own update check: the package is
compared against this repository's releases, the client against the
[TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient/releases)
releases, because the client is released by the vendor independently of the
package and a new version of one does not imply a new version of the other.
The check result is cached for six hours: GitHub allows 60 unauthenticated
requests per hour per address, and the page polls regularly. The "Check now"
button asks GitHub immediately, without waiting for the cache to expire.

The check distinguishes "no update" from "could not check" — the latter is
shown as its own line. With no network it shows the last cached result, marked
as such. A third case is named separately: the installed version is newer than
the latest release (a build from `main`, or a cache that could not be
refreshed) — that is not reported as "up to date".

To update, run `install.sh` again: it stops the service, replaces the package,
installs the client and brings the service back up if it was running. Settings
survive, because `/etc/config/trusttunnel` is declared in `conffiles`.

---

## Two modes

The mode is switched on the Settings tab and changes how traffic is
selected.

### Bypass by list (`selective`) — default

When dnsmasq on the router answers a DNS query for a domain from the
selected lists, it writes the resolved addresses into an nftables set. A
kernel rule marks packets to those addresses, and only those go into the
tunnel. Everything else stays on the kernel's fast path at full link speed.

Pick this mode to bypass blocking without losing speed on the rest of your
traffic. This is the primary scenario, and it requires `dnsmasq-full`.

### Everything through VPN (`full`)

All forwarded LAN traffic is marked. Lists are not used in this mode:
exclusions are handled by the client itself, by SNI, based on the "do not
bypass" list (plus, if **Send the selected lists out directly** is enabled,
the domains from the selected community lists, handed to the client as
exclusions).

Pick this if you need to hide all traffic rather than bypass specific
sites.

### Comparison

| | Bypass by list | Everything through VPN |
| --- | --- | --- |
| Speed of non-bypassed traffic | full, kernel fast path | limited by userspace processing |
| Selected lists | decide what goes into the tunnel | not used (except `full_exclude_lists`) |
| "Do not bypass" | works | works |
| Needs dnsmasq with `nftset` | yes | no |
| Depends on whose DNS LAN clients use | yes | no |

The router's own traffic goes out directly by default in both modes. This
is deliberate: otherwise the client would loop back on itself, and with a
broken tunnel there would be nothing left to fix the router with. Enabled
separately with the **Route the router's own traffic too** checkbox
(`include_router_traffic`).

---

## How it works internally

### Traffic selection

The tun device is created by the CLIENT, not by this package, and it picks the
name itself (usually `tun0`). There is no way to set it: no such key exists in
the client configuration schema. The package originally created the device and
expected the client to attach to it — that assumption turned out to be wrong:
the client silently made its own, ours stayed carrier-less, and marked traffic
went into a dead interface.

So the default route is attached to the client device once it appears. The main
mechanism is a hotplug script: it fires exactly when the device is created, and
covers both the first start and the device being recreated after procd restarts
the client.

Everything else rests on three things:

- routing table `880` with a default route through the client device;
- the rule `ip rule fwmark 0x9527 lookup 880`;
- the package's own nft table `inet trusttunnel`, which sets that mark.

A dedicated table, rather than hooking into `fw4`, is deliberate: it is not
flushed by `fw4 reload` and does not tie the package to firewall4
internals. The ruleset for both modes was accepted by a real `nft -c -f -`
on a live router.

The chain always passes traffic through unmarked in three cases: traffic
that is not from the LAN, traffic to the endpoint's own addresses (otherwise
the client's own connection to the server would go into the tunnel it is
itself establishing), and traffic to private addresses.

Data flow in "bypass by list" mode:

```
allow-domains (selected files)   ─┐
your "bypass" domains             ─┼─→ gen-lists ─→ /var/etc/trusttunnel/dnsmasq.conf
your list URLs                    ─┘                nftset=/domain/4#inet#trusttunnel#tt_bypass4
                                                      nftset=/domain/6#inet#trusttunnel#tt_bypass6
                                                      server=/domain/<list_resolver>
Subnets/IPv4|IPv6/*.lst           ────→ gen-lists ─→ /var/etc/trusttunnel/elements.nft

UCI /etc/config/trusttunnel       ────→ gen-config ─→ /var/etc/trusttunnel/client.toml
your "do not bypass" domains      ────→                exclusions = [...]
```

In "everything through VPN" mode `gen-lists` is not called at all:
`dnsmasq.conf` and `elements.nft` are not created. `client.toml` gets
`exclusions` from the "do not bypass" list and, if `full_exclude_lists` is
enabled, the domains from the selected lists too.

The mechanism was verified end to end on real hardware: with a generated
config in place, querying a bypassed domain from a LAN client caused
dnsmasq to add the resolved addresses to the nftables set automatically.

### Killswitch

Next to the route through the client device in table 880 sits a `blackhole` route with a
high metric. While the device is alive, the primary route wins. As soon as
the device disappears, the kernel removes its route on its own, and marked
traffic falls into the blackhole — dropped, not leaked to the ISP. The
client's built-in killswitch is disabled so two parties aren't managing the
firewall at once.

### DNS

For every domain from the lists, the generator emits not just an `nftset=`
line but also `server=/domain/<resolver>`. Who does the resolving, and how the
query is protected, is decided by `list_dns` with three values.

**`plain` (default)** — ordinary DNS to the address in `list_resolver`. That
address is statically added to the bypass set, so queries for **exactly the
bypassed domains** travel inside the tunnel: the ISP can neither read them nor
substitute the answer. If it could, spoofed addresses would land in the set and
bypass would stop working. Every other query takes the ordinary path, with no
added latency.

**`doh`** — encrypted DNS. The service starts a local `https-dns-proxy` as its
own procd instance and points dnsmasq at it. The query leaves encrypted, but
**directly rather than through the tunnel** — the ISP sees that a resolver was
contacted, not what was asked. The resolver address is not added to the bypass
set: an encrypted query does not need the tunnel.

This mode is what you want when filtering by your own profile matters — NextDNS,
for instance: `https://dns.nextdns.io/<your-id>`. The `https-dns-proxy` package
is deliberately not a dependency: encrypted DNS is not for everyone, and 400 KB
matters on a router with 8 MB of flash. Without it no `server=` lines are
emitted at all — the ISP resolves the list domains, bypass keeps working, and
Diagnostics says what to install.

#### A resolver for the whole network

By default the resolver you set here serves **only the domains from your
lists**: each one gets a `server=/domain/127.0.0.1#5460` line and that is all.
Every other query in the network goes wherever the stock `https-dns-proxy`
pointed dnsmasq — usually Cloudflare. Hence the most common complaint about this
setting: you entered NextDNS and a test page still reports Cloudflare. The test
page is right — `test.nextdns.io` is not in the bypass lists.

The **Use this resolver for the whole network** checkbox (`doh_network`) closes
that gap. While the service runs, it switches the stock `https-dns-proxy` over
to your URL — every instance of it — and restores its settings when stopped.
The dnsmasq config is never touched by us: `noresolv` and
`server=127.0.0.1#5053` are written by that package's own init, which already
has a backup-and-restore mechanism for exactly this.

Every instance is switched, not just the first: their init knows no `disabled`
option and starts each section, while dnsmasq keeps all domain-less `server=`
entries in one pool and spreads queries across them. One forgotten instance
would quietly hand part of the traffic to another resolver.

A conf-dir snippet of our own cannot take the network's DNS over, and this was
verified on a live router with a separate dnsmasq instance: the wildcard domain
`/#/` has no precedence over domain-less `server=` entries and lands in the same
pool. With `server=127.0.0.1#5053` next to `server=/#/127.0.0.1#5460`,
Cloudflare answered. Our resolver would serve "sometimes" — worse than an honest
"never".

Worth knowing before you turn it on:

- dnsmasq is restarted when the service starts and stops, so the network loses
  DNS for a fraction of a second;
- if the resolver stops answering, **the whole network** is left without DNS,
  not just the list domains: dnsmasq has `noresolv` and no other upstream;
- our own instance on `list_doh_port` is not started in this mode, and no
  `server=` lines are emitted for the list domains — they would point at the
  same resolver as the general upstream;
- if you edited `resolver_url` by hand while the checkbox was on, the service
  notices on stop and will **not** overwrite your edit with its backup — but
  the previous values are then lost to it;
- the checkbox is off by default, and upgrading the package does not turn it on.

**`provider`** — no resolver of ours; the domains are resolved by whatever the
router already uses.

Why `plain` cannot do DoT or DoH directly: the value goes into a dnsmasq
`server=` directive, which accepts only a plain address. That is precisely why
encryption is done through a local proxy instead of a field setting.

#### How addresses get into the set

The kernel picks traffic by address, and the addresses are put into the set by
dnsmasq as it answers a query for a listed domain — but only for a query that
reached the upstream. An answer served from dnsmasq's own cache never lands in
the set. Two consequences are worth knowing.

First: applying the settings recreates the nftables table from scratch, so the
accumulated addresses are gone every time. The service therefore flushes the
dnsmasq cache with a HUP — otherwise the next client query would be answered
from that cache, the set would stay empty, and the bypass would silently do
nothing until the TTL expired.

Second: until something asks for a domain **through the router**, its addresses
are not in the set. For the community lists that is fine — there are over a
thousand of them and the set fills as you browse. Your own domains are resolved
by the service itself right after the settings are applied: you have just typed
that domain by hand and expect it to work, while your device usually holds the
address in its own DNS cache already and never asks the router at all.

A device using its own DoH or DoT resolver does not go through the router's
dnsmasq, so its queries never reach this mechanism and list matching does
not apply to it — unless the **Intercept client DNS** checkbox
(`intercept_dns`) is enabled, which redirects UDP/TCP port 53 to the router
and blocks port 853.

### What happens on Save & Apply

The client reads its config once, at startup, so any settings change used to
mean a restart: the tunnel dropped for a few seconds. Worse, the nft table went
down with the client, leaving nothing to mark traffic with — so marked LAN
traffic went out directly. Saving settings opened the very leak this package
protects against.

The service now compares the applied state (`settings.tsv`) with what UCI
exports and does exactly what the changed keys require:

| What changed | What happens | Tunnel |
| --- | --- | --- |
| List auto-update schedule | nothing: cron reads it at runtime | stays up |
| Selected lists, own domains, plain resolver address, LAN devices, killswitch, DNS interception | rules are regenerated and reloaded into the kernel, the route is reattached to the live device | stays up |
| Server address and credentials, certificate, MTU, mode, log level, resolver type for lists | the client restarts, routing is kept — traffic hits the killswitch instead of leaking out directly | drops |
| Routing table number, fwmark, enabling and disabling the service | full restart with routing torn down: there is no other way to remove the previous table and rule | drops |

The classification is a whitelist: any key missing from it gets a full restart.
A needless restart costs a few seconds, while a skipped apply would look like
"the interface shows the new value but the old one is in effect" — a failure
with nothing to diagnose it by. A test checks the list against the settings
schema, so a new option cannot be added without deciding how it applies.

In full mode, editing lists also restarts the client: with **Exclude the
selected lists** enabled they go into the client config rather than into the
dnsmasq rules.

### Where things live

| Path | Contents |
| --- | --- |
| `/etc/config/trusttunnel` | Your settings. Survives a package update |
| `/usr/share/trusttunnel/lists/` | Downloaded lists. Survive a reboot, excluded from config backups |
| `/var/etc/trusttunnel/client.toml` | Generated client config, mode 600 |
| `/var/etc/trusttunnel/settings.tsv` | Settings in flat form for the generators, mode 600 |
| `/var/etc/trusttunnel/endpoint.pem` | Pinned certificate, if set, mode 600 |
| `/var/etc/trusttunnel/dnsmasq.conf` | Generated dnsmasq rules |
| `/var/etc/trusttunnel/elements.nft` | Static nftables set elements |
| `/var/etc/trusttunnel/own.domains` | Your own domains after normalisation — the service resolves them itself to fill the set without waiting for a client query |
| `/tmp/dnsmasq.<section>.d/trusttunnel.conf` | A **copy** (not a link) of the rules dnsmasq reads; the path depends on dnsmasq's UCI section name |
| `/opt/trusttunnel_client/` | The `trusttunnel_client` and `setup_wizard` binaries |

The file in dnsmasq's conf-dir is a plain copy, not a symlink — deliberately.
dnsmasq on OpenWrt runs inside a ujail that does not mount
`/var/etc/trusttunnel`, so a symlink cannot be followed. Verified on a real
router: with a symlink, the log showed `cannot access
…/trusttunnel.conf: No such file or directory`, `FAILED to start up`, and
procd drove dnsmasq into a crash loop — installing the package killed DNS
for the whole network. With a plain copy, dnsmasq starts normally.

---

## Configuring without the interface

The core works independently of LuCI, so it can be configured through UCI
directly.

```bash
# Server
uci set trusttunnel.endpoint.hostname='vpn.example.com'
uci add_list trusttunnel.endpoint.address='203.0.113.10:443'
uci set trusttunnel.endpoint.username='alice'
uci set trusttunnel.endpoint.password='secret'

# Mode
uci set trusttunnel.main.mode='selective'

# Lists
uci add_list trusttunnel.lists.source='Russia/inside-raw.lst'
uci add_list trusttunnel.lists.source='Services/youtube.lst'
uci add_list trusttunnel.lists.subnet='Subnets/IPv4/telegram.lst'

# Your own domains
uci add_list trusttunnel.domains.bypass='example.com'
uci add_list trusttunnel.domains.direct='bank.example'

# Enable and start
uci set trusttunnel.main.enabled='1'
uci commit trusttunnel
/etc/init.d/trusttunnel enable
/etc/init.d/trusttunnel start
```

Download lists and apply the rules without restarting the tunnel:

```bash
/etc/init.d/trusttunnel update_lists
```

Check what came out of it:

```bash
cat /var/etc/trusttunnel/lists.summary
/usr/libexec/trusttunnel/routing status /var/etc/trusttunnel/settings.tsv
```

---

## Full settings reference

Configuration lives in `/etc/config/trusttunnel`. The client files
generated from it live in `/var/etc/trusttunnel/` and **must not be edited
by hand** — they are overwritten on every start.

### `main` section

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `0` | Start the service on boot |
| `mode` | `selective` | `selective` — bypass by list, `full` — everything through VPN |
| `full_exclude_lists` | `0` | `full` mode only: hand the selected lists' domains to the client as exclusions. Thousands of entries increase memory use |
| `log_level` | `info` | `info`, `debug`, `trace` |

### `endpoint` section

| Option | Default | Description |
| --- | --- | --- |
| `hostname` | — | Hostname for the TLS session, required |
| `address` | — | List of `host:port`, at least one required |
| `username`, `password` | — | Credentials, required |
| `protocol` | `http2` | `http2` or `http3` |
| `anti_dpi` | `0` | DPI countermeasures |
| `post_quantum` | `1` | Post-quantum key exchange |
| `skip_verification` | `0` | Accept any certificate |
| `certificate` | — | Pinned certificate, PEM format |
| `has_ipv6` | `1` | Whether the endpoint speaks IPv6 |
| `dns_upstream` | — | DNS servers for queries inside the tunnel. Empty means unfiltered AdGuard DNS |
| `custom_sni` | — | Name sent in the TLS handshake instead of `hostname`, when the server is set up that way |
| `client_random` | — | Client random prefix for the server's scanner protection, `hex[/mask]`; such a server rejects clients without it |

### `network` section

| Option | Default | Description |
| --- | --- | --- |
| `mtu` | `1350` | MTU on the device |
| `early_ack` | `1` | Read the SNI before the connection is made: the vendor's recommendation with external DNS and wildcard exclusions. Client 1.1.5+ |
| `scannable_ports` | `443,80,8080,8008,853` | Ports where the SNI is read; a range is `8080:8090` |
| `preresolve` | `1` | Resolve excluded domains ahead of time, in the background |
| `preresolve_max` | `50` | How many exclusions to pre-resolve per pass |
| `tcp_recv_buf`, `tcp_send_buf` | `0` | TCP window buffers per connection inside the tunnel, bytes; `0` is the client's 256 KB. Client 1.0.63+ |
| `table` | `880` | Routing table |
| `fwmark` | `0x9527` | Firewall mark |
| `lan_devices` | — | Interfaces whose forwarded traffic is considered. Empty takes the `lan` network's device. Set explicitly if you have a guest network |
| `blackhole_on_down` | `1` | Drop marked traffic when the tunnel is down instead of leaking it to the ISP |
| `include_router_traffic` | `0` | Also route the router's own traffic through the tunnel |
| `list_dns` | `plain` | Who resolves the list domains: `plain` — ordinary DNS through the tunnel, `doh` — encrypted via a local proxy, `provider` — whatever the router already uses. `selective` only |
| `list_resolver` | `1.1.1.1` | Resolver address for `plain` mode. Accepts `address#port` |
| `list_doh_url` | empty | DoH resolver URL for `doh` mode, e.g. `https://dns.nextdns.io/<id>` |
| `list_doh_port` | `5460` | Local port the `https-dns-proxy` we start listens on. Unused when `doh_network` is set |
| `doh_network` | `0` | Make the resolver from `list_doh_url` the DNS of the whole network, not only of the list domains: while running, the service switches the stock `https-dns-proxy` over to it and restores its settings on stop. `doh` only |
| `intercept_dns` | `0` | Intercept client DNS: redirect port 53 to the router and block port 853. `selective` only |

### `lists` section

| Option | Default | Description |
| --- | --- | --- |
| `auto_update` | `1` | Update lists on a schedule |
| `update_interval` | `daily` | Reserved; the actual schedule is a cron string |
| `source` | — | List of allow-domains files, e.g. `Russia/inside-raw.lst` |
| `subnet` | — | List of subnet files, e.g. `Subnets/IPv4/telegram.lst` |
| `url` | — | List of custom URLs with additional lists |

### `domains` section

| Option | Description |
| --- | --- |
| `bypass` | Domains to route through the tunnel in addition to the lists |
| `direct` | Domains, IPs, or CIDRs that always go direct. Takes priority over everything else |

---

## Diagnostics

### Log

```bash
logread -e trusttunnel        # everything from the package and the client
logread -f -e trusttunnel     # follow in real time
```

The client's log goes to `logd` — an in-memory ring buffer, no flash writes,
no rotation.

### Kernel state

```bash
# What the package itself sees
/usr/libexec/trusttunnel/routing status /var/etc/trusttunnel/settings.tsv

# Device, rule, table
ip link show "$(cat /var/etc/trusttunnel/device)"   # the client device
ip rule show | grep 880
ip route show table 880

# Sets: what actually landed in the bypass
nft list set inet trusttunnel tt_bypass4
nft list set inet trusttunnel tt_endpoint4
```

### Check whether traffic is going through the tunnel

The easiest way is the **Status and test** tab → **Compare external IP**.
Manually:

```bash
curl --interface "$(cat /var/etc/trusttunnel/device)" https://api.ipify.org   # external IP through the tunnel
curl https://api.ipify.org                   # external IP directly
```

Different addresses mean the tunnel is working.

### Common problems

**The service won't start, log mentions the CA bundle.** `ca-bundle` is not
installed. Install it, or pin the server's certificate in settings, or
disable certificate verification.

**Log complains about the certificate right after boot.** The clock has not
synced yet. Check that NTP is working.

**Bypass doesn't work for a specific site.** Check the domain with **Check a
domain**. Common causes: the domain isn't in any selected list; the device
uses its own DoH resolver and the query never reaches the router's dnsmasq;
the domain is on the "do not bypass" list.

**Bypass stopped working after switching modes.** In "everything through
VPN" mode the lists are not used. That is expected.

**Speed dropped on all traffic.** "Everything through VPN" mode is probably
enabled. For bypassing blocks without touching the rest of your traffic,
use "bypass by list".

**The `tt_bypass4` set is empty.** dnsmasq hasn't answered a query for a
bypassed domain yet. Sets fill up as domains are actually resolved, not in
advance. Query any listed domain from a LAN client and check again.

---

## Limitations

An honest list of what the package does not do, and what to do about it.

- **A device using its own DoH or DoT resolver bypasses list matching
  entirely.** Its DNS queries never reach the router's dnsmasq, so its
  addresses never land in the bypass set. The remedy is the "intercept
  client DNS" checkbox (`intercept_dns`), but it breaks setups where a
  custom resolver is used on purpose — off by default for that reason.
- **A list entry like `example.com` is matched together with all of its
  subdomains.** That is how domain matching works in dnsmasq. As a
  consequence, an entry for a bare TLD (say, `ua`) covers that whole zone —
  worth keeping in mind when picking such lists.
- **Domains with non-ASCII characters are rejected.** Use punycode
  (`xn--…`). The number of rejected entries is shown in the interface.
- **The router's own traffic goes out directly by default.** Enabled with a
  separate checkbox, "Route the router's own traffic too"
  (`include_router_traffic`).
- **Community-list domains enter the set on first query, not immediately.** An
  address shows up in the set once dnsmasq answers a query for that domain.
  Your own domains are exempt — the service warms them up itself; doing the
  same for a thousand-plus list domains would be a very different cost on every
  apply. A device that already holds the address in its own DNS cache will not
  ask the router at all: if a site keeps going direct, flush the cache on the
  device (`ipconfig /flushdns`, restart the browser).
- **A CDN address shared between domains can pull the wrong one into the
  tunnel.** The kernel selects by address, not by name, so one IP shared by
  several names gets marked together. The precise remedy is the "do not
  bypass" list: the client matches it by SNI, after address-based
  selection, not by IP.
- **Guest networks are not picked up automatically.** Add their interfaces
  to `lan_devices`.
- **Only OpenWrt 25.12 and newer is supported.** The package is built
  around `apk`, which replaced `opkg`; older versions will not be
  supported.
- **Multiple server profiles and failover between them are not
  implemented.** One server; multiple addresses for that one server are
  fine.

---

## Updating

```bash
sh -c "$(wget -O - https://raw.githubusercontent.com/NooBiToo/TrustTunnelOpenWrt/main/install.sh)"
```

Running the installer again updates both the package and the client
binary. Settings in `/etc/config/trusttunnel` are left untouched.

---

## Uninstalling

```bash
# Stop and disable the service
/etc/init.d/trusttunnel stop
/etc/init.d/trusttunnel disable

# Remove the packages. The i18n package must be in the same call: it depends on
# the main one, so `apk del luci-app-trusttunnel` alone silently does nothing —
# it reports "not removed due to" and exits zero.
apk del luci-i18n-trusttunnel-ru luci-app-trusttunnel

# Remove the client binaries and downloaded lists
rm -rf /opt/trusttunnel_client /usr/share/trusttunnel

# Remove the cron job
sed -i '/trusttunnel update_lists/d' /etc/crontabs/root
/etc/init.d/cron restart
```

The `trusttunnel` firewall zone and the forwarding rule from `lan` remain
in `/etc/config/firewall` — remove them by hand if you no longer need them:

```bash
uci show firewall | grep trusttunnel   # find the zone and forwarding sections
uci delete firewall.<zone_section>
uci delete firewall.<forwarding_section>
uci commit firewall
/etc/init.d/firewall restart
```

Check that nothing is left in the kernel:

```bash
nft list table inet trusttunnel   # should report that the table doesn't exist
ip rule show | grep 880           # should be empty
ip route show table 880           # no routes should remain
```

Settings in `/etc/config/trusttunnel` remain after removing the package, so
a reinstall does not lose your configuration. Remove the file by hand if
you don't want that.

---

## Donate

The package is free. If it helped you, you can support the development
with crypto — addresses below.

**TON**

```
UQD_JkHxRPrnkVPV560LT5zshYhe4ErkH-KALsKaNgPkJRmx
```

**Tron (TRC-20, e.g. USDT)**

```
TJCjmqQu5p8g9DbVPY7FdC59LvtZCcjFVn
```

**Ethereum / Polygon (EVM)** — one address for both networks:

```
0xd886FFA25b8816dDe1b7339D1ae2Ea4Ac9624b45
```

**Solana**

```
3XZGBNf2FuJ1ZKFrtWZXxLtfFKqxEVfW2JnmUuGtdqMx
```

---

## Keywords

OpenWrt, LuCI, TrustTunnel, VPN client for router, DPI bypass, censorship
circumvention, selective bypass, split tunneling, selective routing, domain
lists, allow-domains, itdoginfo, podkop, dnsmasq, nftables, fwmark, killswitch,
TUN, procd, apk, router firmware, YouTube in Russia, Telegram, Discord,
one-command install

---

## License and acknowledgements

The package is distributed under the **GPL-2.0** license. Full text in
[LICENSE](LICENSE).

- [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) — the protocol,
  server, and client, Apache 2.0.
- [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) —
  the community domain lists.
- [itdoginfo/podkop](https://github.com/itdoginfo/podkop) — a reference
  implementation of bypass-by-list on OpenWrt, GPL-2.0. The approach to
  traffic selection through dnsmasq and nftables was checked against it.
