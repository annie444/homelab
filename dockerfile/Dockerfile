FROM nixos/nix:latest

RUN nix-channel --update

COPY nix.conf /etc/nix/nix.conf

RUN nix-env -iA nixpkgs.openssh
RUN nix-env -iA nixpkgs.ssh-to-age
RUN nix-env -iA nixpkgs.age
RUN nix-env -iA nixpkgs.sops
RUN nix-env -iA nixpkgs.openssl
