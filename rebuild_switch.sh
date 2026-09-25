#!/bin/sh

nixos-rebuild --flake .#${HOSTNAME} --sudo switch
