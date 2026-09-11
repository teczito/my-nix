{ pkgs, ... }:

{
  services.ollama = {
    enable = true;

    # CPU inference. `services.ollama.acceleration` no longer exists -- the
    # backend is chosen by which package you install. Swap this for
    # pkgs.ollama-cuda or pkgs.ollama-rocm when a card lands, and import the
    # matching GPU module from the host; nothing else here changes.
    package = pkgs.ollama-cpu;

    # Loopback only, deliberately. Reaching it from another machine is an ssh
    # tunnel (`ssh -L 11434:localhost:11434 <host>`), not an open port: ollama
    # has no authentication of its own, so anything that can reach the port can
    # run and pull models.
    host = "127.0.0.1";
    port = 11434;
  };

  # A browser front-end for the above. Off until asked for; it wants its own
  # decision about what it listens on.
  # services.open-webui.enable = true;
}
