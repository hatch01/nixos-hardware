{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.raspberry-pi."4".overlays;
  linux_rpi4 = pkgs.linuxKernel.packages.linux_rpi4.kernel;

  # dtbos = pkgs.stdenvNoCC.mkDerivation {
  #   pname = "dtbos";
  #   version = linux_rpi4.version;
  #   nativeBuildInputs = [ linux_rpi4 ];

  #   # Patch bcmxxx to bcm2711
  #   buildCommand = ''
  #     mkdir -p $out
  #     cd $out
  #     cp -r ${linux_rpi4}/dtbs/overlays/* .

  #     # Replace bcmXXX with bcm2711(cpu of raspberry pi 4) in the overlay files
  #     sed -i 's/bcm[0-9]*/bcm2711/g' *.dtbo
  #   '';

  #   meta = {
  #     inherit (linux_rpi4.meta) homepage license;
  #     description = "DTBOs for the Raspberry Pi 4";
  #   };
  # };

  overlayNames = (
    builtins.map (name: lib.removeSuffix ".dtbo" name) (
      builtins.attrNames (builtins.readDir "${linux_rpi4}/dtbs/overlays")
    )
  );

  deprecateOverlayOption =
    lastTwo: overlayName:
    lib.mkRemovedOptionModule (
      [
        "hardware"
        "raspberry-pi"
        "4"
      ]
      ++ lastTwo
    ) "Please use new syntax : hardware.raspberry-pi.\"4\".overlays = [ \"${overlayName}\" ];";
in
{
  imports = [
    (deprecateOverlayOption [ "backlight" "enable" ] "rpi-backlight-overlay")
  ];

  options.hardware.raspberry-pi."4".overlays = lib.mkOption {
    type = lib.types.listOf (
      lib.types.either lib.types.str (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.enum overlayNames;
              description = "Name of the overlay";
            };
            params = lib.mkOption {
              type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.bool);
              default = { };
              description = "Parameters to pass to the overlay";
            };
          };
        }
      )
    );
    default = [ ];
    description = ''
      List of overlays to apply for Raspberry Pi 4. Can be either:
      - String: overlay name (e.g., "iqaudio-dac")
      - Attribute set with name and params (e.g., { name = "iqaudio-dac"; params = { "24db_digital_gain" = "1"; }; })

      Only the following overlays are allowed: ${lib.concatStringsSep ", " overlayNames}
    '';
    example = [
      "tc358743"
      "vc4-kms-v3d-pi4"
      {
        name = "iqaudio-dac";
        params = {
          "24db_digital_gain" = true;
          "auto_mute_amp" = true;
        };
      }
    ];
  };

  config = lib.mkIf (cfg != [ ]) {
    hardware.deviceTree = {
      filter = "bcm2711-rpi-4*.dtb";
      overlays = builtins.map (
        overlay:
        if builtins.isString overlay then
          # Simple overlay without parameters
          "${pkgs.stdenvNoCC.mkDerivation {
            pname = "dtbo-${overlay}";
            version = linux_rpi4.version;
            nativeBuildInputs = [ linux_rpi4 ];

            buildCommand = ''
              mkdir -p $out
              cp ${linux_rpi4}/dtbs/overlays/${overlay}.dtbo $out/
              # Replace bcmXXX with bcm2711(cpu of raspberry pi 4) in the overlay files
              sed -i 's/bcm[0-9]*/bcm2711/g' $out/${overlay}.dtbo
            '';
          }}/${overlay}.dtbo"
        else
          # Overlay with parameters - create custom overlay
          "${pkgs.stdenvNoCC.mkDerivation {
            pname = "dtbo-${overlay.name}-with-params";
            version = linux_rpi4.version;
            nativeBuildInputs = [ linux_rpi4 pkgs.dtc ];

            buildCommand = ''
              mkdir -p $out
              
              # Decompile the original overlay to get source
              dtc -I dtb -O dts -o overlay.dts ${linux_rpi4}/dtbs/overlays/${overlay.name}.dtbo
              
              # Apply parameter modifications
              cp overlay.dts overlay-modified.dts
              
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (param: value: let
                propValue = if lib.isBool value then (if value then "1" else "0") else toString value;
              in ''
                # Modify the overlay to include the parameter
                # This is a simplified approach that sets properties in __overlay__ sections
                sed -i '/^[[:space:]]*__overlay__[[:space:]]*{/,/^[[:space:]]*};/ {
                  /^[[:space:]]*${lib.escapeShellArg param}[[:space:]]*[;=]/d
                  /^[[:space:]]*status[[:space:]]*=/a\
                  \t\t\t${param} = <${propValue}>;
                }' overlay-modified.dts || true
              '') overlay.params)}
              
              # Replace bcmXXX with bcm2711 for Pi 4 compatibility
              sed -i 's/bcm[0-9]*/bcm2711/g' overlay-modified.dts
              
              # Compile back to dtbo
              dtc -I dts -O dtb -o $out/${overlay.name}.dtbo overlay-modified.dts
            '';
          }}/${overlay.name}.dtbo"
      ) cfg;
    };
  };
}
