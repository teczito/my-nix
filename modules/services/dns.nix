# AdGuard Home as the LAN's resolver: ad-blocking, plus a place for simple
# `name -> LAN IP` rewrites later. Why AdGuard Home rather than Blocky or
# Technitium is in docs/server-roadmap.md.
#
# mutableSettings stays at its default (true): what is declared here is merged
# over the state file on every start and wins, while anything set only in the
# web UI (query-log retention, client names, ...) survives restarts.
{ ... }:

let
  # The server's address on the LAN. Must not move -- clients are handed this
  # as their resolver -- so the router has to keep it reserved for this host.
  lanAddress = "192.168.68.105";
in
{
  services.adguardhome = {
    enable = true;

    # Admin UI on the LAN at http://192.168.68.105:3000, behind the login
    # below. Plain HTTP; moving it behind Caddy is on the roadmap.
    host = lanAddress;
    port = 3000;
    openFirewall = true;

    settings = {
      # The admin login. With settings declared, AdGuard skips its setup wizard,
      # so without this entry the UI would have no login at all. The value is a
      # bcrypt hash (`htpasswd -nB ruben`), never the password; being declared
      # here, it overrides anything changed in the UI on every start.
      users = [
        {
          name = "ruben";
          password = "$2y$05$l5DDupy.PGWFqHWdppnuVeJosj/auk0FxTjzMkp..5SOUEW1sQ4Vu";
        }
      ];

      dns = {
        # Explicit addresses, never 0.0.0.0: libvirt's default network runs its
        # own dnsmasq on 192.168.122.1:53, and a wildcard bind here makes
        # whichever of the two starts second fail with "address already in use".
        bind_hosts = [
          "127.0.0.1"
          lanAddress
        ];
        port = 53;

        # Encrypted upstreams only. The bootstrap servers resolve nothing but
        # the DoH hostnames themselves.
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];
        bootstrap_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };

      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
      ];
    };
  };

  # Binding lanAddress fails until DHCP has actually handed it out, so wait for
  # the network rather than racing it (network.target, the module's default,
  # only means the stack is up, not that the address is).
  systemd.services.adguardhome = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # The module's openFirewall only covers the web UI; the resolver port is ours
  # to open.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
