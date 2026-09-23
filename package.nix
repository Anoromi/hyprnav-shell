{ runCommand, makeWrapper, quickshell }:

runCommand "hyprnav-shell" {
  nativeBuildInputs = [ makeWrapper ];
} ''
  mkdir -p "$out/bin"
  cp -r ${./shell} "$out/shell"
  makeWrapper ${quickshell}/bin/qs "$out/bin/hyprnav-shell" \
    --unset HNS_SCREEN \
    --set-default HNS_COMPONENTS switcher,grid,badges,caption \
    --add-flags "-p $out/shell"
''
