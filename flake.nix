{
  description = "A seedbox download monitor";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = inputs@{ self, flake-parts, nix2container, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: let
        env = {
          MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
          MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
        };
      in {
        devShells.default = pkgs.mkShell {
          inherit env;

          packages = with pkgs; [
            beamPackages.elixir
            esbuild
            just
            openssl
            tailwindcss_4
          ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            inotify-tools
          ];
        };

        packages = let
          pname = "boxmon";
          version =
            let v = builtins.getEnv "BOXMON_VERSION";
            in if v != "" then v else (self.dirtyShortRev or self.shortRev or "unknown");
          src = ./.;

          default = pkgs.beamPackages.mixRelease {
            inherit pname version src env;

            mixFodDeps = pkgs.beamPackages.fetchMixDeps {
              inherit version src;
              pname = "${pname}-deps";
              hash = "sha256-S86o2PCuZdq0tXV9bCj/9ontcEb/ZaWhtN1rThqWnEo=";
            };

            postBuild = ''
              mix do deps.loadpaths --no-deps-check, assets.deploy
              mix do deps.loadpaths --no-deps-check, phx.digest
            '';
          };

          container = nix2container.packages.${system}.nix2container.buildImage {
            name = "ghcr.io/scareyo/${pname}";
            tag = version;
            copyToRoot = [ pkgs.dockerTools.caCertificates ];
            config.entrypoint = [ "${default}/bin/boxmon" "start" ];
          };
        in {
          inherit default container;
        };
      };
    };
}
