{ ... }:

{
  virtualisation.docker.enable = true;
  # `virtualisation.docker.storageDriver` is deliberately NOT set here: the
  # right value depends on the filesystem backing /var/lib/docker, which is a
  # property of the machine. Each host sets its own.
}
