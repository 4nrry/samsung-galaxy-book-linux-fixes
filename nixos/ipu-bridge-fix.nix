# Loads the out-of-tree ipu-bridge override so libcamera learns the sensor
# rotation for upside-down mounted sensors (rotation=180 on Galaxy Book5
# convertibles).
#
# Unlike webcam-fix-book5, this needs no libcamera overlay or relay stack.
# The override only replaces the ipu-bridge module, so stock libcamera
# orients every consumer itself. Use it on native in-tree intel-ipu7 stacks
# where the override would otherwise never engage and PipeWire apps show a
# flipped image.
#
#   hardware.samsungGalaxyBook.ipuBridgeFix.enable = true;
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.samsungGalaxyBook.ipuBridgeFix;
  inherit (config.boot) kernelPackages;
  inherit (kernelPackages) kernel;
  kernelUsesClang = kernel.stdenv.cc.isClang or false;
  cc =
    if kernelUsesClang
    then pkgs.llvmPackages.clang-unwrapped
    else pkgs.gcc;
  clangMakeFlags = lib.optionalString kernelUsesClang (lib.escapeShellArgs kernel.commonMakeFlags);
  # modules_install, not a bare copy: nixpkgs overrides Kbuild's cmd_sign so
  # the install step writes a <module>.ko.cer beside each module, and newer
  # aggregateModules fails the system build when one is missing (#130).
  # Nixpkgs without that flag installs exactly as before.
  installMakeFlags =
    if kernelUsesClang
    then clangMakeFlags
    else lib.escapeShellArgs (builtins.filter (lib.hasPrefix "cmd_sign=") (kernel.commonMakeFlags or []));
in {
  options.hardware.samsungGalaxyBook.ipuBridgeFix = {
    enable = lib.mkEnableOption "out-of-tree ipu-bridge override reporting sensor rotation";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      initrd.kernelModules = ["ipu-bridge"];
      kernelModules = ["ipu-bridge"];
      extraModulePackages = [
        (pkgs.stdenvNoCC.mkDerivation {
          pname = "ipu-bridge-fix";
          version = "1.1-${kernelPackages.kernel.modDirVersion}";
          src = ../webcam-fix-book5/ipu-bridge-fix;

          nativeBuildInputs =
            kernel.moduleBuildDependencies
            ++ [kernelPackages.kernel.dev cc pkgs.gnumake pkgs.perl]
            ++ lib.optionals kernelUsesClang [pkgs.llvmPackages.lld];

          buildPhase = ''
            make -C ${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build \
              M=$PWD modules ${clangMakeFlags}
          '';

          installPhase = ''
            make -C ${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build \
              M=$PWD modules_install INSTALL_MOD_PATH=$out INSTALL_MOD_DIR=extra \
              DEPMOD=true ${installMakeFlags}
          '';
        })
      ];
    };
  };
}
