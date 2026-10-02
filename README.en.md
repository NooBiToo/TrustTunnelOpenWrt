# TrustTunnel for OpenWrt

[Русский](README.md) · [Releases](https://github.com/NooBiToo/TrustTunnelOpenWrt/releases) · [Detailed guide](GUIDE.en.md) · [Report a bug](https://github.com/NooBiToo/TrustTunnelOpenWrt/issues)

**Selected sites through a VPN, everything else direct. Configuration and diagnostics in LuCI.**

`luci-app-trusttunnel` runs the [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel)
client on your **OpenWrt 25.12+** router. Devices on your home network use the tunnel through
the router without needing a separate VPN client on each device.

- **Selective routing:** [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) lists, custom domains and exclusions.
- **Browser-based configuration:** import a server config, select lists and manage the service in LuCI.
- **Built-in diagnostics:** tunnel status, domain checks, endpoint ping and external IP comparison.
- **Two modes:** route by list or send all LAN internet traffic through the VPN with exclusions; a killswitch for selected traffic.

TrustTunnel is an open VPN protocol originally developed by AdGuard VPN,
with HTTPS-based transport and features designed to resist DPI.

**Domain list selection in LuCI**

![TrustTunnel settings in LuCI: categories, services, subnets and automatic list updates](Screenshot_3.png)

The screenshots show the Russian interface; the LuCI app is also available in English.

## Quick start

### Requirements

- A router running **OpenWrt 25.12 or newer**, with LuCI and the `apk` package manager.
- SSH access to the router and free storage for the client binary and dependencies.
- **A TrustTunnel server and its connection config.** This package installs the router client;
  set up the server separately using the [official instructions](https://github.com/TrustTunnel/TrustTunnel#quick-start).
- A supported client architecture: `aarch64`, `armv7l`, `mips`, `mipsel` or `x86_64`.
  Check yours with `uname -m`.

OpenWrt 24.10 and earlier releases using `opkg` are unsupported.
Selective routing requires `dnsmasq-full` with `nftset` support. The installer checks for it
and asks for confirmation before replacing stock `dnsmasq`.

### 1. Install

Run over SSH **on the router**:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/NooBiToo/TrustTunnelOpenWrt/main/install.sh)"
```

The installer checks compatibility and installs dependencies, the LuCI package and the client binary.
Replacing `dnsmasq` with `dnsmasq-full` briefly restarts DNS.
The service is disabled after installation so you can configure it first.

### 2. Configure

1. Open **Services → TrustTunnel → Settings**.
2. On the **Server** tab, click **Import…** and paste your server's config,
   or enter the connection settings manually.
3. On the **Lists** tab, select the services or categories you need.
   Add custom domains and exclusions on the **My domains** tab if needed.
4. Enable startup on boot, click **Save & Apply**, then **Start** on the status page.

### 3. Verify

On the **Diagnostics** page, check the configuration and enter a domain such as `youtube.com`.
The app explains whether it is selected for routing through the tunnel and why.
Use the external IP comparison to check the tunnel's exit address alongside your direct connection.

## Interface

**Status:** service controls, routing mode, list counts, and package and client versions.

![TrustTunnel status in LuCI: running service, domain and subnet counts, package and client versions](Screenshot_1.png)

**Diagnostics:** configuration checks, domain checks, endpoint ping and external IP comparison.

![TrustTunnel diagnostics in LuCI: check results, domain check, ping and external IP comparison](Screenshot_2.png)

## Two modes

| Mode | Traffic through the tunnel | Use case |
|---|---|---|
| **Bypass by list** — default | Selected domain and subnet lists plus your custom domains | Use a VPN for specific services while other traffic stays direct |
| **Everything through VPN** | LAN internet traffic, with exclusions | Tunnel internet traffic for the whole home network |

Routing the router's own traffic is a separate option.
The Telegram daemon from the separate [tgws-openwrt](https://github.com/NooBiToo/tgws-openwrt) project connects directly: its sockets are marked `0x7467` and excluded from the tunnel.
See [routing modes](GUIDE.en.md#two-modes) and [killswitch](GUIDE.en.md#killswitch) for details.

## Things to know

- Selective routing matches domains through the router's DNS.
  Devices using their own DoH/DoT may bypass that matching.
- A service may use multiple domains; use the community lists and domain checker.
- Sites sharing an IP address may cause additional domains to be routed through the tunnel.
- One server is supported; multiple profiles and automatic failover are not implemented yet.
- Add guest network interfaces to the LAN interface settings explicitly.

See the complete [limitations and workarounds](GUIDE.en.md#limitations).

## Documentation

- [Detailed guide](GUIDE.en.md): installation, interface, configuration without LuCI, updates and removal.
- [Settings reference](SETTINGS.ru.md) (Russian): options and examples; an English summary is available [in the guide](GUIDE.en.md#full-settings-reference).
- [DNS and routing internals](GUIDE.en.md#how-it-works-internally).
- [Diagnostics and troubleshooting](GUIDE.en.md#diagnostics).
- [Architecture compatibility](GUIDE.en.md#which-routers-are-supported).

To update, run the installation command again. It updates the package and client while preserving settings.

## Support the project

**If this package helped you, give it a ⭐ [on GitHub](https://github.com/NooBiToo/TrustTunnelOpenWrt).**
It helps other users discover the project.

Found a bug or tested the package on your router? [Open an issue](https://github.com/NooBiToo/TrustTunnelOpenWrt/issues)
with your router model, OpenWrt version, package version and test results.
Remove passwords and other connection details before posting logs.

[Donate to support development](GUIDE.en.md#donate).

## License and acknowledgements

[GPL-2.0](LICENSE). The package uses the [TrustTunnel client](https://github.com/TrustTunnel/TrustTunnelClient)
and [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) lists.
The selective routing approach was checked against [itdoginfo/podkop](https://github.com/itdoginfo/podkop).
This is a community integration, not an official AdGuard product.
