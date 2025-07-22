{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.raspberry-pi."4".audio;
  overlays = import ./overlay_utils.nix { inherit lib; };
  inherit (overlays) simple-overlay;
in
{
  options.hardware = {
    raspberry-pi."4".audio = {
      enable = lib.mkEnableOption ''
        configuration for audio
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.deviceTree = {
      overlays = [
        # Equivalent to dtparam=audio=on
        (simple-overlay {
          target = "audio";
          status = "okay";
        })
      ];
    };

    # set tsched=0 in pulseaudio config to avoid audio glitches
    # see https://wiki.archlinux.org/title/PulseAudio/Troubleshooting#Glitches,_skips_or_crackling
    hardware.pulseaudio.configFile = lib.mkOverride 990 (
      pkgs.runCommand "default.pa" { } ''
        sed 's/module-udev-detect$/module-udev-detect tsched=0/' ${config.hardware.pulseaudio.package}/etc/pulse/default.pa > $out
      ''
    );
  };
}
