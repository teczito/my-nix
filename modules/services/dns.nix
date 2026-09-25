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

    # Admin UI on loopback only for now: with settings declared, AdGuard skips
    # its setup wizard, and with no `users` entry the UI has no login at all.
    # Reach it with `ssh -L 3000:localhost:3000 192.168.68.105`. Before moving
    # it onto the LAN, add a bcrypt user under settings.users.
    host = "127.0.0.1";
    port = 3000;

    settings = {
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
