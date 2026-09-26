# Tools for the disposable lab compositor: a Wayland virtual seat client, a
# pointer/wheel injector, a timestamped key injector (hns-lab-keys), Cage
# with xdg-shell v6 (needed by Aquamarine for nested Hyprland), wtype for key
# injection and wf-recorder for capture. Build with `nix-build lab-tools -o lab-tools/result`.
{ pkgs ? import <nixpkgs> { } }:
let
  seat = pkgs.runCommand "hns-lab-seat" {
    nativeBuildInputs = [ pkgs.stdenv.cc pkgs.pkg-config pkgs.wayland-scanner ];
    buildInputs = [ pkgs.wayland pkgs.libxkbcommon ];
  } ''
    wayland-scanner client-header ${./protocols/virtual-keyboard-unstable-v1.xml} keyboard.h
    wayland-scanner private-code ${./protocols/virtual-keyboard-unstable-v1.xml} keyboard.c
    wayland-scanner client-header ${./protocols/wlr-virtual-pointer-unstable-v1.xml} pointer.h
    wayland-scanner private-code ${./protocols/wlr-virtual-pointer-unstable-v1.xml} pointer.c
    mkdir -p $out/bin
    cc -I. ${./seat.c} keyboard.c pointer.c $(pkg-config --cflags --libs wayland-client xkbcommon) -o $out/bin/hns-lab-seat
    cc -I. ${./scroll.c} pointer.c $(pkg-config --cflags --libs wayland-client) -o $out/bin/hns-lab-scroll
    cc -I. ${./keys.c} keyboard.c $(pkg-config --cflags --libs wayland-client xkbcommon) -o $out/bin/hns-lab-keys
  '';
  cage = pkgs.cage.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace cage.c --replace-fail 'wlr_xdg_shell_create(server.wl_display, 5)' 'wlr_xdg_shell_create(server.wl_display, 6)'
    '';
  });
  # Python with GTK4 bindings for the demo "agent worker" app.
  demoPython = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  demoEnv = pkgs.buildEnv {
    name = "hns-demo-env";
    paths = [ demoPython pkgs.gtk4 pkgs.libadwaita pkgs.gobject-introspection pkgs.adwaita-icon-theme pkgs.graphene pkgs.pango.out pkgs.harfbuzz pkgs.gdk-pixbuf pkgs.glib.out pkgs.cairo pkgs.hicolor-icon-theme ];
  };
in pkgs.buildEnv {
  name = "hyprnav-shell-lab-tools";
  paths = [ seat cage pkgs.wtype pkgs.wf-recorder demoEnv ];
}
