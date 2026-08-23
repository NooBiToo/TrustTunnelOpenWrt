# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-trusttunnel
PKG_VERSION:=1.0.5
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=TrustTunnelOpenWrt contributors

LUCI_TITLE:=LuCI support for TrustTunnel with domain bypass lists
LUCI_DESCRIPTION:=Runs the TrustTunnel client on OpenWrt and routes selected \
	domains through the tunnel using itdoginfo/allow-domains lists.
LUCI_DEPENDS:=+luci-base +kmod-tun +ip-full +curl +ca-bundle +ucode-mod-math
# Иначе luci.mk подставит адрес самого LuCI, и `apk info` отправлял бы за
# поддержкой не туда.
LUCI_URL:=https://github.com/NooBiToo/TrustTunnelOpenWrt
LUCI_PKGARCH:=all

# Без этого объявления обновление пакета ЗАТРЁТ /etc/config/trusttunnel
# дефолтами, то есть уничтожит адрес сервера, пароль, сертификат и выбранные
# списки, и выключит службу. Файлы под /etc/config защищёнными автоматически
# НЕ становятся. Проверено на живом OpenWrt: apk ведёт список защищённых
# файлов на пакет — у штатного dnsmasq-full это
# /lib/apk/packages/dnsmasq-full.conffiles, где /etc/config/dhcp перечислен
# вместе с контрольной суммой.
#
# Блок обязан стоять ДО include luci.mk, и это не вопрос стиля. Последняя
# строка luci.mk вызывает BuildPackage, а тот захватывает список немедленным
# присваиванием: `KEEP_$(1):=$(strip $(call Package/$(1)/conffiles))` в
# include/package-pack.mk. include подставляет текст на месте, поэтому захват
# происходит раньше, чем парсер дойдёт до объявления, написанного после — и
# список замирает пустым. Объявление выглядит присутствующим и не работает,
# что хуже его отсутствия. Так же поступают штатные luci-app-amule и
# luci-app-alwaysonline.
define Package/luci-app-trusttunnel/conffiles
/etc/config/trusttunnel
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

# Биты исполнения выставляются ЯВНО, а не берутся из репозитория.
#
# luci.mk копирует каталог root/ командой `cp -pR`, то есть сохраняет права
# файлов-источников. Разработка шла на Windows, где у файловой системы нет бита
# исполнения, поэтому git записал все скрипты как 100644 — и в собранный .apk
# уехали init-скрипт и генераторы, которые нельзя запустить. На роутере это
# выглядело так: служба «не запускается» и НИ ОДНОЙ строки в журнале, потому что
# procd не может выполнить файл. Диагностировать почти нечем.
#
# Дефект дожил до релиза, потому что на стенде я выкладывал файлы через scp и
# каждый раз делал chmod +x руками — своя же привычка его и скрывала.
#
# Режимы в индексе git тоже исправлены, но полагаться только на них нельзя:
# они теряются при скачивании zip-архивом, при переносе через файловую систему
# без прав и при работе на Windows у любого, кто соберёт пакет заново.
define Build/Compile
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/init.d/trusttunnel
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/uci-defaults/40-luci-trusttunnel
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/hotplug.d/net/40-trusttunnel
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/fetch-lists
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/gen-config
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/gen-lists
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/normalize
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/routing
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/uci-export
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/warm-sets
	# records.sh подключается через `.`, запускать его не нужно.
	chmod 0644 $(PKG_BUILD_DIR)/root/usr/libexec/trusttunnel/records.sh
endef
