# server: services roadmap

Not part of the build — a plan, not config. Written 2026-09-25 after a discussion about what
`server` should run beyond what's already there (local LLM, VM host, containers, compiling). Revisit
and update as pieces land or the plan changes; delete sections once they're actually implemented and
the reasoning has moved into the module itself.

## Current state (baseline this plan builds on)

- **LLM**: `modules/services/llm.nix` — ollama, CPU inference, bound to `127.0.0.1`. No auth on ollama
  itself, so loopback-only is load-bearing, not incidental.
- **Hardware**: installed and running at `192.168.68.105` (`enp11s0`, DHCP from the router at
  `192.168.68.1`). The IP still needs a DHCP reservation on the router before DNS is pointed at it.
- **Web**: Caddy already **runs** on the server, because the meal-planner flake's module enables it for
  the `teczito.duckdns.org` vhost and opens 80/443/8080. `modules/services/caddy.nix` is a separate
  thing: it is **not imported anywhere**, and is written as a single PHP app server (its own phpfpm
  pool), not a shared reverse-proxy hub.
- **DNS**: AdGuard Home in `modules/services/dns.nix`, imported by `hosts/server`. It builds, but as of
  2026-09-25 it has **not been deployed** yet, so LAN resolution is still whatever the router hands out.
- **Secrets**: none set up. Nothing currently needs one.
- **Isolation**: both docker and libvirtd are already imported (`docker.nix`, `virtualisation.nix`),
  so both a container path and a full-VM path already exist — nothing new to add there, just a rule
  for when to reach for which.
- **Pattern to keep following**: one file per concern under `modules/services/`, the host's
  `default.nix` opts in explicitly. Firewall ports are opened in the module that owns the port
  (see `meal-planner.nix`'s `openFirewall`), never as a blanket rule in `networking.nix`.

## Planned pieces

### 1. Reverse proxy — repurpose Caddy as a shared front door

`caddy.nix` today is one app's config, not infrastructure. Split it:

- A thin `modules/services/caddy.nix`: just `services.caddy.enable = true`, no app-specific bits.
- Move the phpfpm pool and PHP-specific `virtualHosts` entry into whatever module actually needs PHP
  (or drop it if nothing does yet).
- Each web-facing service module contributes its own `services.caddy.virtualHosts."<name>"` entry —
  same "module owns its concern" shape as `environment.systemPackages` already uses across this repo.
- Internal-only services get Caddy's own local CA; anything facing the internet reuses the
  `teczito.duckdns.org` pattern already established by meal-planner.

### 2. DNS — AdGuard Home as the LAN resolver

Confirmed available in this flake's nixpkgs: `services.adguardhome`, `services.blocky`, and
`services.technitium-dns-server` all exist as real modules (checked via `nix eval` against
`nixosConfigurations.server.options`, not assumed).

Decision: **AdGuard Home**, not Blocky or Technitium.

- Blocky is config-only (YAML, no UI, no DHCP) — the infra-as-code purity buys little here since this
  repo already edits Nix directly for everything; a UI is a real benefit for the rare case someone
  else on the LAN needs to look at something.
- Technitium is the most capable (real authoritative zones + full recursion) but is overkill unless
  internal DNS grows past a handful of hostname rewrites. It's the upgrade path if that ever happens —
  strict superset of what AdGuard Home's rewrite table does.
- AdGuard Home gets ad-blocking plus simple `name → LAN IP` rewrites, which is all that's needed today
  (e.g. `ollama.internal`, `caddy` vhost names).

Done (in `modules/services/dns.nix`, reasoning in its comments):

- Listens on `127.0.0.1` and `192.168.68.105` explicitly, never `0.0.0.0`, which would clash with
  libvirt's dnsmasq on `192.168.122.1:53`.
- Port 53 (TCP and UDP) is opened in the module. AdGuard's `openFirewall` covers only the UI port.
- Upstreams are DoH (Quad9, Cloudflare). Plain `9.9.9.9`/`1.1.1.1` are used only to look up those two.
- The AdGuard DNS filter list is on.
- The admin UI is on `127.0.0.1:3000` only. Declaring settings skips AdGuard's wizard, so with no
  `settings.users` the UI would have no login.

Still to do:

- Deploy it: on the server, `git pull && ./rebuild_switch.sh`. Then check that
  `dig @192.168.68.105 example.com` resolves and `dig @192.168.68.105 doubleclick.net` returns `0.0.0.0`.
- Reserve `192.168.68.105` on the router, then point the router's DHCP DNS option at it.
- **IPv6 bypasses AdGuard as things stand.** The router advertises its own IPv6 DNS server
  (`fd8e:c1da:5885::1`), so IPv6-capable clients skip AdGuard. Either turn that off on the router, or
  add the server's DHCPv6 address (`fd8e:c1da:5885::7a1` at the time of writing) to `bind_hosts`.
- Add an admin user (a bcrypt hash from `htpasswd -nB`), then move the UI onto the LAN, either
  directly or as a Caddy vhost.

### 3. Secrets — sops-nix, added on first need

Nothing today needs a secret (ollama has none; meal-planner manages its own). The trigger for adding
this is the first real one — most likely AdGuard Home's admin password, or an API key for whatever
service comes after DNS.

Decision: **sops-nix over agenix**, specifically because this repo already has SSH host keys
(`modules/common/ssh.nix`) — sops-nix decrypts using the existing host key, so there's no separate
keypair to provision the way agenix wants. Don't pre-provision this; add it when the first secret
actually shows up.

### 4. Isolation policy — make the existing split a rule, not an accident

The repo already treats ollama and Caddy as native NixOS modules while docker/libvirtd exist
separately for other things. Write that down as policy so it doesn't erode as more services get
added:

- **Native `modules/services/*.nix` module** — default choice, whenever nixpkgs has a decent module
  for it (AdGuard Home, Caddy, ollama all qualify). Gets the module system's config surface for free
  and composes with everything else the way this repo already works.
- **docker** — only for third-party apps with no nixpkgs module, or that only ship as a container
  image not worth packaging.
- **libvirtd VM** — only for whole-OS isolation: untrusted workloads, or something that needs its own
  kernel/network stack. Not a substitute for docker or a native module.

### 5. Firewall

No change in approach — keep opening ports in the module that owns them (already `meal-planner.nix`'s
pattern), and apply it to DNS (53) and Caddy (80/443) the same way.

## Suggested order of implementation

1. ~~Add `modules/services/dns.nix` (AdGuard Home), wire it into `hosts/server/default.nix`.~~
   Written and building. Done ahead of the Caddy split, which turned out not to block it.
2. Deploy DNS, reserve the IP, and point the router's DHCP DNS option at the server. Verify LAN
   clients resolve through it, and handle the IPv6 bypass above.
3. Split `caddy.nix` into the generic shell + move the PHP-specific bits out. It must coexist with the
   Caddy config that meal-planner's module already contributes.
4. Add sops-nix only once a concrete secret needs it. The AdGuard admin password is probably fine as a
   bcrypt hash in Nix, which makes this less urgent than first thought.

## Open questions for whenever this gets picked back up

- ~~Static LAN IP?~~ The server is at `192.168.68.105`. It still needs the DHCP reservation, which is a
  router setting, not a repo change.
- Should AdGuard Home's admin UI be reachable from the LAN directly, or only through Caddy? For now it
  is on loopback only, until an admin user exists.
- Any services beyond LLM/web/DNS in mind yet, or genuinely undecided ("...things I haven't thought of
  as of today")? Revisit the isolation policy above once a concrete third-party app is the trigger.
