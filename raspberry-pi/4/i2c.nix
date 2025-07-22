{ config, lib, ... }:

let
  cfg = config.hardware.raspberry-pi."4";
  overlays = import ./overlay_utils.nix { inherit lib; };
  inherit (overlays) simple-overlay;
in
{
  options.hardware.raspberry-pi."4" = {
    i2c0 = {
      enable = lib.mkEnableOption ''
        Turn on the VideoCore I2C bus (maps to /dev/i2c-22) and enable access from the i2c group.
        After a reboot, i2c-tools (e.g. i2cdetect -F 22) should work for root or any user in i2c.
      '';
      frequency = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          interface clock-frequency
        '';
      };
    };
    i2c1 = {
      enable = lib.mkEnableOption ''
        Turn on the ARM I2C bus (/dev/i2c-1 on GPIO pins 3 and 5) and enable access from the i2c group.
        After a reboot, i2c-tools (e.g. i2cdetect -F 1) should work for root or any user in i2c.
      '';
      frequency = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          interface clock-frequency
        '';
      };
    };
  };
  config.hardware = lib.mkMerge [
    (lib.mkIf cfg.i2c0.enable {
      i2c.enable = lib.mkDefault true;
      deviceTree = {
        overlays = [
          (simple-overlay {
            target = "i2c0";
            status = "okay";
            inherit (cfg.i2c0) frequency;
          })
        ];
      };
    })
    (lib.mkIf cfg.i2c1.enable {
      i2c.enable = lib.mkDefault true;
      deviceTree = {
        overlays = [
          (simple-overlay {
            target = "i2c1";
            status = "okay";
            inherit (cfg.i2c1) frequency;
          })
        ];
      };
    })
  ];
}
