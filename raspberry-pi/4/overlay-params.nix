{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.raspberry-pi."4".overlay-params;
  linux_rpi4 = pkgs.linuxKernel.packages.linux_rpi4.kernel;

  # Function to generate a custom overlay with parameters
  makeParameterizedOverlay = overlayName: params: let
    # Read the original overlay file
    originalDtbo = "${linux_rpi4}/dtbs/overlays/${overlayName}.dtbo";
    
    # Create a custom overlay with parameters applied
    customOverlay = pkgs.stdenvNoCC.mkDerivation {
      pname = "${overlayName}-with-params";
      version = linux_rpi4.version;
      nativeBuildInputs = [ pkgs.dtc ];
      
      buildCommand = ''
        mkdir -p $out
        
        # Decompile the original overlay to get the source
        dtc -I dtb -O dts -o overlay.dts ${originalDtbo}
        
        # Apply parameter modifications using sed
        cp overlay.dts overlay-modified.dts
        
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (param: value: let
          # Convert parameter name to property format (replace underscores with hyphens for some cases)
          propName = param;
          # Convert value to appropriate format
          propValue = if lib.isBool value then (if value then "1" else "0") else toString value;
        in ''
          # Add or modify parameter in __overrides__ section
          # This is a simplified approach - real implementation would need more sophisticated DTS manipulation
          sed -i '/^[[:space:]]*__overrides__[[:space:]]*{/,/^[[:space:]]*};/ {
            /^[[:space:]]*${lib.escapeShellArg propName}[[:space:]]*=/c\
            ${lib.escapeShellArg propName} = "${propValue}";
          }' overlay-modified.dts
          
          # Also try to set the property directly if it exists in the overlay section
          sed -i '/^[[:space:]]*__overlay__[[:space:]]*{/,/^[[:space:]]*};/ {
            s/^[[:space:]]*${lib.escapeShellArg propName}[[:space:]]*;/${propName};/
            /^[[:space:]]*${lib.escapeShellArg propName}[[:space:]]*;/i\
            ${propName} = <${propValue}>;
          }' overlay-modified.dts
        '') params)}
        
        # Replace bcmXXX with bcm2711 for Pi 4 compatibility
        sed -i 's/bcm[0-9]*/bcm2711/g' overlay-modified.dts
        
        # Compile back to dtbo
        dtc -I dts -O dtb -o $out/${overlayName}.dtbo overlay-modified.dts
      '';
    };
  in "${customOverlay}/${overlayName}.dtbo";

  # Function to create device tree overlay specification with parameters
  makeOverlaySpec = overlay: 
    if lib.isString overlay then
      overlay
    else if lib.isAttrs overlay && overlay ? name then
      if overlay ? params && overlay.params != {} then
        makeParameterizedOverlay overlay.name overlay.params
      else
        overlay.name
    else
      throw "Invalid overlay specification: ${toString overlay}";

  # Get available overlay names from the kernel
  overlayNames = (
    builtins.map (name: lib.removeSuffix ".dtbo" name) (
      builtins.attrNames (builtins.readDir "${linux_rpi4}/dtbs/overlays")
    )
  );

in
{
  options.hardware.raspberry-pi."4".overlay-params = {
    enable = lib.mkEnableOption "parameterized overlay support";

    overlays = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.enum overlayNames;
            description = "Name of the overlay";
          };
          params = lib.mkOption {
            type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.bool);
            default = {};
            description = ''
              Parameters to pass to the overlay. These will be baked into the overlay
              at build time by modifying the device tree source.
              
              Common parameters include:
              - For audio overlays: 24db_digital_gain, auto_mute_amp, unmute_amp
              - For display overlays: rotate, fps, debug
              - For GPIO overlays: gpiopin, active_low
            '';
          };
        };
      }));
      default = [];
      description = ''
        List of overlays with parameters to apply for Raspberry Pi 4.
        
        Can be either:
        - String: simple overlay name (e.g., "vc4-kms-v3d-pi4")
        - Attribute set: overlay with parameters
        
        Parameters are applied by modifying the device tree source at build time,
        similar to how the Raspberry Pi firmware processes dtparam= settings.
      '';
      example = [
        "vc4-kms-v3d-pi4"
        {
          name = "iqaudio-dac";
          params = {
            "24db_digital_gain" = true;
            "auto_mute_amp" = true;
            "unmute_amp" = false;
          };
        }
        {
          name = "spi1-1cs";
          params = {
            cs0_pin = "18";
          };
        }
      ];
    };
  };

  config = lib.mkIf (cfg.enable && cfg.overlays != []) {
    # Ensure basic overlay support is enabled
    hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = lib.mkDefault true;

    # Apply the overlays with parameters
    hardware.deviceTree = {
      filter = "bcm2711-rpi-4*.dtb";
      overlays = map makeOverlaySpec cfg.overlays;
    };
  };

  # Provide some common overlay configurations as convenience options
  options.hardware.raspberry-pi."4".audio = {
    iqaudio-dac = {
      enable = lib.mkEnableOption "IQaudio DAC with common parameters";
      
      digitalGain24db = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable 24dB digital gain";
      };
      
      autoMuteAmp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto mute amplifier when not in use";
      };
      
      unmuteAmp = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Unmute amplifier on startup";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.hardware.raspberry-pi."4".audio.iqaudio-dac.enable {
      hardware.raspberry-pi."4".overlay-params = {
        enable = true;
        overlays = [{
          name = "iqaudio-dac";
          params = {
            "24db_digital_gain" = config.hardware.raspberry-pi."4".audio.iqaudio-dac.digitalGain24db;
            "auto_mute_amp" = config.hardware.raspberry-pi."4".audio.iqaudio-dac.autoMuteAmp;
            "unmute_amp" = config.hardware.raspberry-pi."4".audio.iqaudio-dac.unmuteAmp;
          };
        }];
      };
    })
  ];
}