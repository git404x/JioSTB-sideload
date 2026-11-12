{
  description = "JioSTB-sideload: Universal Exploitation, TR-069 ACS Penetration, and FOSS Provisioning Toolkit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          pythonEnv = pkgs.python3.withPackages (ps: with ps; [
            cryptography
            pycryptodome
            requests
          ]);
        in
        {
          default = pkgs.mkShell {
            name = "jiostb-sideload-env";

            buildInputs = with pkgs; [
              # Android device management & low-latency display
              android-tools
              scrcpy

              # Cryptographic tooling & Python TLS MITM
              pythonEnv
              openssl

              # Network redirection & DHCP/DNS server
              dnsmasq
              curl
              jq

              # Container orchestration for GenieACS & MongoDB
              podman
              podman-compose
            ];

            shellHook = ''
              echo "================================================================="
              echo " 🚀 JioSTB-sideload Environment Loaded"
              echo " Run './stb check' or './stb wizard' to get started."
              echo "================================================================="
            '';
          };
        });
    };
}
