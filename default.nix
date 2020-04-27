{ system ? builtins.currentSystem, configuration ? null
, nixpkgs ? import <nixpkgs> { }, extraKernelConfigFile ? "config"
, kernelSrcDir ? ./kernel, debianImage ? "debian-qemu-image.img"
, debianImageSize ? "2G", debianRoot ? "debian-root"
, rootPassword ? "pwFuerRoot", ... }@args:
with nixpkgs.pkgs;
let
  currentDirectory = "${builtins.toPath ./.}";

  writeInitialHashedPassword = password:
    runCommand "write-initial-hashed-password" {
      nativeBuildInputs = [ mkpasswd ];
    } ''
      mkpasswd -m sha-512 ${password} > $out
    '';

  getInitialHashedPassword = password:
    builtins.readFile "${writeInitialHashedPassword password}";

  rootInitialHashedPassword = getInitialHashedPassword rootPassword;

  bootstrapDebian = writeScript "bootstrap-debian-for-kernel-development" ''
    debian_image="${currentDirectory}/${debianImage}"
    debian_image_size="${debianImageSize}"
    mount_point="${currentDirectory}/${debianRoot}"
    mkdir -p "$mount_point"
    if [[ ! -f "$debian_image" ]]; then
      ${qemu}/bin/qemu-img create "$debian_image" "$debian_image_size"
      ${e2fsprogs}/bin/mkfs.ext2 "$debian_image"
    fi
    if ! ${utillinux}/bin/mountpoint -q "$mount_point"; then
      sudo ${utillinux}/bin/mount -o loop "$debian_image" "$mount_point"
      sudo ${debootstrap}/bin/debootstrap --arch amd64 unstable "$mount_point"
      sudo chroot debian-root /bin/bash -c 'echo hello world'
      echo "${rootPassword}\n${rootPassword}" | sudo chroot debian-root /bin/passwd root
      sudo ${utillinux}/bin/umount "$mount_point"
    fi
  '';

  makeKernelVersion = src:
    stdenvNoCC.mkDerivation {
      name = "my-kernel-version";
      inherit src;
      phases = "installPhase";
      # make kernelversion also works.
      installPhase = ''
        set -x
        s="$(< "$src/Makefile")"
        get() {
          awk "/^$1 = / "'{print $3}' <<< "$s"
        }
        printf '%s.%s.%s%s' "$(get VERSION)" "$(get PATCHLEVEL)" "$(get SUBLEVEL)" "$(get EXTRAVERSION)" | tee $out
      '';
    };

  getKernelVersion = src: builtins.readFile "${makeKernelVersion src}";

  kernelSrc = let
    gitignoreSrc = pkgs.fetchFromGitHub {
      owner = "hercules-ci";
      repo = "gitignore";
      rev = "2ced451";
      sha256 = "0fc5bgv9syfcblp23y05kkfnpgh3gssz6vn24frs8dzw39algk2z";
    };
  in with import gitignoreSrc { inherit lib; }; gitignoreSource kernelSrcDir;

  kernelVersion = getKernelVersion kernelSrc;

  latestConfigFile = linuxPackages_latest.kernel.configfile;

  defaultConfigFile = (linuxConfig {
    src = kernelSrc;
    version = kernelVersion;
  }).overrideAttrs ({ prePatch ? "", ... }: {
    prePatch = linuxPackages_latest.kernel.prePatch + prePatch;
  });

  # We need to merge some `CONFIG_` to make qemu happy.
  allConfigFiles = let
    p = "${currentDirectory}/${extraKernelConfigFile}";
    extraConfig = lib.optionals (builtins.pathExists p) [
      "${builtins.path {
        name = "extra-kernel-config";
        path = p;
      }}"
    ];
    # in [ defaultConfigFile latestConfigFile ] ++ extraConfig;
  in [ latestConfigFile ];

  mergedConfigFile = (stdenv.mkDerivation {
    name = "merged-kernel-config";
    src = kernelSrc;
    phases = "unpackPhase prePatchPhase installPhase";
    prePatchPhase = linuxPackages_latest.kernel.prePatch;
    # make qemu happy with `CONFIG_EXPERIMENTAL=y`.
    depsBuildBuild =
      [ buildPackages.stdenv.cc buildPackages.bison buildPackages.flex ];
    installPhase = ''
      set -x
      KCONFIG_CONFIG=$out RUNMAKE=false "$src/scripts/kconfig/merge_config.sh" ${
        builtins.concatStringsSep " " allConfigFiles
      }
      grep -q '^CONFIG_EXPERIMENTAL=' $out && sed -i 's/^CONFIG_EXPERIMENTAL=.*/CONFIG_EXPERIMENTAL=y/' $out || echo 'CONFIG_EXPERIMENTAL=y' >> $out
    '';
  }).overrideAttrs ({ prePatch ? "", ... }: {
    prePatch = linuxPackages_latest.kernel.prePatch + prePatch;
  });

  customKernel = linuxPackages_custom {
    src = kernelSrc;
    version = kernelVersion;
    configfile = "${mergedConfigFile}";
  };

  nixosConfiguration = { config, pkgs, ... }: {
    imports = [ ] ++ lib.optionals (configuration != null) [ configuration ];

    boot = {
      kernelPackages = customKernel;
      kernelParams = [ "boot.shell_on_fail" "boot.trace" ];
    };

    environment = {
      enableDebugInfo = true;
      etc = let
        getHome = x: builtins.elemAt (builtins.split ":" x) 10;
        entries = builtins.filter (x: x != "" && x != [ ])
          (builtins.split "\n" (builtins.readFile /etc/passwd));
        homes = builtins.map getHome entries;
        currentDirectory = "${builtins.toPath ./.}";
        possibleUserHomes =
          builtins.filter (x: lib.hasPrefix x currentDirectory) homes;
        keyFiles = builtins.filter (x: builtins.pathExists x)
          (builtins.map (x: "${x}/.ssh/authorized_keys") possibleUserHomes);
        keys = builtins.concatStringsSep "\n"
          (builtins.map (x: builtins.readFile x) keyFiles);
      in lib.optionalAttrs (keys != "") {
        "ssh/authorized_keys.d/root" = {
          text = builtins.trace ''
            Added the following keys for ssh access.
            ${keys}
          '' keys;
          mode = "0444";
        };
      };
    };

    users.users.root.initialHashedPassword = rootInitialHashedPassword;

    services.sshd.enable = true;
  };

  nixos = import (nixpkgs.path + "/nixos/") {
    inherit system;
    configuration = nixosConfiguration;
  };
in nixos // {
  inherit bootstrapDebian allConfigFiles defaultConfigFile latestConfigFile
    mergedConfigFile customKernel kernelSrc;
}
