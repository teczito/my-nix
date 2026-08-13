{
  lib,
  fetchurl,
  makeDesktopItem,
  appimageTools,
}:
let
  pname = "saleae-logic-2";
  version = "2.4.46";
  src = fetchurl {
    url = "https://downloads2.saleae.com/logic2/Logic-${version}-linux-x64.AppImage";
    hash = "sha256-goMu0NMWZwHX9PffV6YgtyGiOIPgz+jy6OlaLmcg1vI=";
  };
  desktopItem = makeDesktopItem {
    name = "saleae-logic-2";
    exec = "saleae-logic-2";
    icon = "Logic";
    comment = "Software for Saleae logic analyzers";
    desktopName = "Saleae Logic";
    genericName = "Logic analyzer";
    categories = [ "Development" ];
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # The FHS sandbox mounts a tmpfs on /etc and only links in an allowlist of
  # host entries, so /etc/udev is missing inside it. Logic 2 refuses to start
  # with "rules directory does not exist, expected /etc/udev/rules.d", so bind
  # the host directory in (it is a symlink into /etc/static on NixOS, which
  # bwrap resolves on the host side).
  extraBwrapArgs = [
    "--ro-bind-try /etc/udev/rules.d /etc/udev/rules.d"
  ];

  extraInstallCommands =
    let
      appimageContents = appimageTools.extract { inherit pname version src; };
    in
    ''
      mkdir -p $out/etc/udev/rules.d
      cp ${appimageContents}/usr/lib/logic/resources/udev/99-SaleaeLogic.rules $out/etc/udev/rules.d/
      mkdir $out/share
      ln -s ${desktopItem}/share/applications $out/share/
      install -Dm644 ${appimageContents}/usr/lib/logic/resources/linux-x64/LogicIcon.png \
        $out/share/pixmaps/Logic.png
    '';

  extraPkgs =
    pkgs: with pkgs; [
      wget
      unzip
      glib
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrender
      libxtst
      nss
      nspr
      dbus
      gdk-pixbuf
      gtk3
      pango
      atk
      cairo
      expat
      libxrandr
      libxscrnsaver
      alsa-lib
      at-spi2-core
      cups
      libxcrypt-legacy
    ];

  meta = {
    homepage = "https://www.saleae.com/";
    changelog = "https://ideas.saleae.com/f/changelog/";
    description = "Software for Saleae logic analyzers";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [
      j-hui
      newam
    ];
  };
}
