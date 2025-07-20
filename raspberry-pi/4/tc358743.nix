{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.raspberry-pi."4".tc358743;
in
{
  options.hardware = {
    raspberry-pi."4".tc358743 = {
      enable = lib.mkEnableOption ''
        Enable support for the Toshiba TC358743 HDMI-to-CSI-2 converter.

        This can be tested with a plugged in converter device and for example
        running ustreamer (which starts webservice providing a camera stream):
        ''${pkgs.ustreamer}/bin/ustreamer --persistent --dv-timings
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.deviceTree = {
      filter = lib.mkForce "bcm2711-rpi-4-b.dtb";
      overlays = [
        {
          name = "tc358743-overlay";
          dtsText = builtins.replaceStrings [ "bcm2835" ] [ "bcm2711" ] (
            builtins.readFile "${pkgs.linuxKernel.kernels.linux_rpi4.src}/arch/arm/boot/dts/overlays/tc358743-overlay.dts"
          );
        }
      ];
    };
  };
}
