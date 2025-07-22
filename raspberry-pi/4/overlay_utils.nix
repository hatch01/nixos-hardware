{ lib }:

let
  /*
    Creates a simple device tree overlay that sets a target's status and optional frequency.

    Example:
      simple-overlay {
        target = "i2c1";
        status = "okay";
        frequency = 400000;
      }
  */
  simple-overlay =
    {
      # The device tree target (e.g. "i2c1", "audio")
      target,
      # The status to set (usually "okay" or "disabled")
      status,
      # Optional clock frequency
      frequency ? null,
    }:
    {
      name = "${target}-${status}-overlay";
      dtsText = ''
        /dts-v1/;
        /plugin/;
        / {
          compatible = "brcm,bcm2711";
          fragment@0 {
            target = <&${target}>;
            __overlay__ {
              status = "${status}";
              ${lib.optionalString (frequency != null) "clock-frequency = <${builtins.toString frequency}>"}
            };
          };
        };
      '';
    };

in
{
  inherit simple-overlay;
}
