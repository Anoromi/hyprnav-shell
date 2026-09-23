{
  description = "hyprnav Quickshell desktop shell";

  # Quickshell 0.3.1 supplies the Networking module used by this shell.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forEachSystem (pkgs:
        let
          hyprnav-shell = pkgs.callPackage ./package.nix { };
        in {
          inherit hyprnav-shell;
          quickshell = pkgs.quickshell;
          default = hyprnav-shell;
        });
    };
}
