FROM nixos/nix:latest

RUN nix-channel --update

COPY nix.conf /etc/nix/nix.conf

RUN nix-env -iA nixpkgs.openssh
