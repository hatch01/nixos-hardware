{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.raspberry-pi."4".overlays;
  linux_rpi4 = pkgs.linuxKernel.packages.linux_rpi4.kernel;
  overlayNames = (
    builtins.map (name: lib.removeSuffix ".dtbo" name) (
      builtins.attrNames (builtins.readDir "${dtbos}")
    )
  );

  dtbos = pkgs.stdenvNoCC.mkDerivation {
    pname = "dtbos";
    version = linux_rpi4.version;
    nativeBuildInputs = [ linux_rpi4 ];

    # Patch bcmxxx to bcm2711
    buildCommand = ''
      mkdir -p $out
      cd $out
      cp -r ${linux_rpi4}/dtbs/overlays/* .

      # Replace bcmXXX with bcm2711(cpu of raspberry pi 4) in the overlay files
      sed -i 's/bcm[0-9]*/bcm2711/g' *.dtbo
    '';

    meta = {
      inherit (linux_rpi4.meta) homepage license;
      description = "DTBOs for the Raspberry Pi 4";
    };
  };
in
{
  options.hardware.raspberry-pi."4".overlays = lib.mkOption {
    type = lib.types.listOf (lib.types.enum overlayNames);
    default = [ ];
    description = ''
      List of overlay names like in dtoverlay param in config.txt to apply for Raspberry Pi 4.
      Only the following overlays are allowed: ${lib.concatStringsSep ", " overlayNames}
    '';
    example = [
      "tc358743"
      "vc4-kms-v3d-pi4"
    ];
  };

  config = lib.mkIf (cfg != [ ]) {
    hardware.deviceTree = {
      filter = "bcm2711-rpi-4*.dtb";
      overlays = builtins.map (overlay:
        if builtins.isString overlay then
          "${dtbos}/${overlay}.dtbo"
        else
          "${dtbos}/${overlay.name}.dtbo ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") overlay.params)}"
      ) cfg;
    };
  };
}
