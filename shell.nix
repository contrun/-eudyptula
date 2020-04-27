{ pkgs ? import <nixpkgs> {} }:

(pkgs.buildFHSUserEnv {
  name = "linux-kernel-build";
  targetPkgs = pkgs: (with pkgs;
  [
    getopt
    flex
    bison
    libelf
    ncurses.dev
    openssl.dev
    gcc
    gnumake
    bc
    fakeroot
  ]);
  runScript = "bash";
}).env
