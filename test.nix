with import <nixpkgs> { };
let currentDirectory = "${builtins.toPath ./.}";
in runCommand "simple-test" { } ''
  set -x
  touch $out
  id
  touch /var/cache/ccache/test
  ls -lha /var/cache/ccache/test
  touch "${currentDirectory}/test/test"
  ls -lha "${currentDirectory}/test"
''
