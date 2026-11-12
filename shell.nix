# Traditional nix-shell compatibility wrapper importing flake.nix
let
  flake = import (
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      node = lock.nodes.nixpkgs.locked;
    in
    fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/${node.rev}.tar.gz";
      sha256 = node.narHash;
    }
  ) {};
in
(import ./flake.nix).outputs.devShells.${builtins.currentSystem}.default or flake.mkShell {
  name = "jiostb-sideload-env";
  buildInputs = with flake; [
    android-tools
    scrcpy
    openssl
    dnsmasq
    curl
    jq
    podman
    podman-compose
    (python3.withPackages (ps: with ps; [ cryptography pycryptodome requests ]))
  ];
}
