{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.raspberry-pi."4".overlay-with-params;
  linux_rpi4 = pkgs.linuxKernel.packages.linux_rpi4.kernel;

  # Function to create a parameterized overlay using device tree manipulation
  makeParameterizedOverlay = overlayName: params: let
    # Create the parameterized overlay derivation
    parameterizedOverlay = pkgs.stdenvNoCC.mkDerivation {
      pname = "${overlayName}-parameterized";
      version = linux_rpi4.version;
      nativeBuildInputs = [ pkgs.dtc pkgs.perl ];

      # Include the ovmerge-like parameter application logic
      buildCommand = ''
        mkdir -p $out
        
        # Copy the original overlay
        cp ${linux_rpi4}/dtbs/overlays/${overlayName}.dtbo original.dtbo
        
        # Decompile to get the source
        dtc -I dtb -O dts -o overlay.dts original.dtbo
        
        # Apply bcm2711 compatibility
        sed -i 's/bcm[0-9]*/bcm2711/g' overlay.dts
        
        # Create a perl script to apply parameters like ovmerge does
        cat > apply_params.pl << 'PERL_EOF'
use strict;

my $file = 'overlay.dts';
my $content;
{
  local $/;
  open my $fh, '<', $file or die "Cannot open $file: $!";
  $content = <$fh>;
  close $fh;
}

${lib.concatStringsSep "\n" (lib.mapAttrsToList (param: value: let
  # Convert boolean/string values appropriately
  paramValue = if lib.isBool value then 
    (if value then "1" else "0") else toString value;
  paramName = param;
in ''
# Apply parameter: ${paramName} = ${paramValue}
if ($content =~ /__overrides__\s*\{[^}]*${lib.escapeShellArg paramName}\s*=\s*<([^>]+)>[^}]*\}/s) {
  my $target_ref = $1;
  $target_ref =~ s/^&//;
  
  # Find the target node and apply the parameter
  if ($content =~ /(\b$target_ref:\s*__overlay__\s*\{[^}]*)\};/s) {
    my $overlay_content = $1;
    
    # Add or modify the property based on parameter type
    if ("${paramValue}" eq "1" || "${paramValue}" eq "0") {
      # Boolean property
      if ("${paramValue}" eq "1") {
        $overlay_content .= "\n\t\t\t${paramName};";
      }
      # For "0", we don't add the property (absence = false for boolean)
    } else {
      # Value property
      $overlay_content .= "\n\t\t\t${paramName} = <${paramValue}>;";
    }
    
    $content =~ s/(\b$target_ref:\s*__overlay__\s*\{[^}]*)};/$overlay_content\n\t\t};/s;
  }
}

# Special handling for common audio overlay parameters
if ("${paramName}" eq "24db_digital_gain" && "${paramValue}" eq "1") {
  $content =~ s/(iqaudio[^;]*;)/$1\n\t\t\tiqaudio,24db_digital_gain;/g;
}
if ("${paramName}" eq "auto_mute_amp" && "${paramValue}" eq "1") {
  $content =~ s/(iqaudio[^;]*;)/$1\n\t\t\tiqaudio-dac,auto-mute-amp;/g;
}
if ("${paramName}" eq "unmute_amp" && "${paramValue}" eq "1") {
  $content =~ s/(iqaudio[^;]*;)/$1\n\t\t\tiqaudio-dac,unmute-amp;/g;
}
'') params)}

# Write the modified content back
open my $out_fh, '>', $file or die "Cannot write $file: $!";
print $out_fh $content;
close $out_fh;
PERL_EOF

        # Apply the parameters
        perl apply_params.pl
        
        # Compile back to dtbo
        dtc -I dts -O dtb -o $out/${overlayName}.dtbo overlay.dts
        
        # Debug: also output the modified source for inspection
        cp overlay.dts $out/${overlayName}.dts
      '';
      
      meta = {
        description = "Parameterized device tree overlay for ${overlayName}";
      };
    };
  in "${parameterizedOverlay}/${overlayName}.dtbo";

  # Function to create overlay specification
  makeOverlaySpec = overlay:
    if lib.isString overlay then
      # Simple overlay - just apply bcm2711 patch
      let
        simpleOverlay = pkgs.stdenvNoCC.mkDerivation {
          pname = "dtbo-${overlay}";
          version = linux_rpi4.version;
          nativeBuildInputs = [ linux_rpi4 ];

          buildCommand = ''
            mkdir -p $out
            cp ${linux_rpi4}/dtbs/overlays/${overlay}.dtbo $out/
            sed -i 's/bcm[0-9]*/bcm2711/g' $out/${overlay}.dtbo
          '';
        };
      in "${simpleOverlay}/${overlay}.dtbo"
    else if lib.isAttrs overlay && overlay ? name then
      if overlay ? params && overlay.params != {} then
        makeParameterizedOverlay overlay.name overlay.params
      else
        # Overlay object without parameters
        let
          simpleOverlay = pkgs.stdenvNoCC.mkDerivation {
            pname = "dtbo-${overlay.name}";
            version = linux_rpi4.version;
            nativeBuildInputs = [ linux_rpi4 ];

            buildCommand = ''
              mkdir -p $out
              cp ${linux_rpi4}/dtbs/overlays/${overlay.name}.dtbo $out/
              sed -i 's/bcm[0-9]*/bcm2711/g' $out/${overlay.name}.dtbo
            '';
          };
        in "${simpleOverlay}/${overlay.name}.dtbo"
    else
      throw "Invalid overlay specification: ${toString overlay}";

  # Get available overlay names
  overlayNames = (
    builtins.map (name: lib.removeSuffix ".dtbo" name) (
      builtins.attrNames (builtins.readDir "${linux_rpi4}/dtbs/overlays")
    )
  );

in
{
  options.hardware.raspberry-pi."4".overlay-with-params = {
    enable = lib.mkEnableOption "advanced overlay support with parameters";

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
              Parameters to pass to the overlay. These are applied by modifying the
              device tree source before compilation, similar to how dtparam works
              in the Raspberry Pi firmware.
              
              Common parameters for audio overlays:
              - 24db_digital_gain: Enable 24dB digital gain (boolean)
              - auto_mute_amp: Auto mute amplifier when not in use (boolean)  
              - unmute_amp: Unmute amplifier on startup (boolean)
              
              Parameters are mapped to device tree properties based on the overlay's
              __overrides__ section.
            '';
          };
        };
      }));
      default = [];
      description = ''
        List of device tree overlays to apply with optional parameters.
        
        Examples:
        - Simple: "vc4-kms-v3d-pi4"
        - With params: { name = "iqaudio-dac"; params = { "24db_digital_gain" = true; }; }
        
        Parameters are processed similar to Raspberry Pi firmware's dtparam system,
        by modifying the overlay source before compilation.
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

    debugOutput = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include .dts source files in output for debugging";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.overlays != []) {
    # Ensure device tree support is enabled
    hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = lib.mkDefault true;

    # Apply the overlays
    hardware.deviceTree = {
      filter = "bcm2711-rpi-4*.dtb";
      overlays = map makeOverlaySpec cfg.overlays;
    };

    # Add debug info if requested
    environment.etc = lib.mkIf cfg.debugOutput (
      lib.listToAttrs (
        lib.imap0 (i: overlay:
          lib.nameValuePair "dt-overlays/overlay-${toString i}-${
            if lib.isString overlay then overlay else overlay.name
          }.info" {
            text = ''
              Overlay: ${if lib.isString overlay then overlay else overlay.name}
              Parameters: ${if lib.isString overlay then "none" else 
                lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: "${k}=${toString v}") 
                  (overlay.params or {}))}
              Source: ${makeOverlaySpec overlay}
            '';
          }
        ) cfg.overlays
      )
    );
  };

  # Convenience options for common overlays
  options.hardware.raspberry-pi."4".common-overlays = {
    iqaudio-dac = {
      enable = lib.mkEnableOption "IQaudio DAC overlay";
      digitalGain24db = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable 24dB digital gain";
      };
      autoMuteAmp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto mute amplifier";
      };
      unmuteAmp = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Unmute amplifier on startup";
      };
    };

    hifiberry-dac = {
      enable = lib.mkEnableOption "HiFiBerry DAC overlay";
    };

    spi-devices = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          bus = lib.mkOption {
            type = lib.types.enum ["spi0" "spi1"];
            description = "SPI bus to enable";
          };
          cs_pins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Chip select pins";
          };
        };
      });
      default = [];
      description = "SPI device configurations";
    };
  };

  config = lib.mkMerge [
    # IQaudio DAC convenience config
    (lib.mkIf config.hardware.raspberry-pi."4".common-overlays.iqaudio-dac.enable {
      hardware.raspberry-pi."4".overlay-with-params = {
        enable = true;
        overlays = [{
          name = "iqaudio-dac";
          params = lib.filterAttrs (_: v: v != false) {
            "24db_digital_gain" = config.hardware.raspberry-pi."4".common-overlays.iqaudio-dac.digitalGain24db;
            "auto_mute_amp" = config.hardware.raspberry-pi."4".common-overlays.iqaudio-dac.autoMuteAmp;
            "unmute_amp" = config.hardware.raspberry-pi."4".common-overlays.iqaudio-dac.unmuteAmp;
          };
        }];
      };
    })

    # HiFiBerry DAC convenience config  
    (lib.mkIf config.hardware.raspberry-pi."4".common-overlays.hifiberry-dac.enable {
      hardware.raspberry-pi."4".overlay-with-params = {
        enable = true;
        overlays = ["hifiberry-dac"];
      };
    })

    # SPI devices convenience config
    (lib.mkIf (config.hardware.raspberry-pi."4".common-overlays.spi-devices != []) {
      hardware.raspberry-pi."4".overlay-with-params = {
        enable = true;
        overlays = map (spi: {
          name = "${spi.bus}-${toString (length spi.cs_pins)}cs";
          params = lib.listToAttrs (
            lib.imap0 (i: pin: 
              lib.nameValuePair "cs${toString i}_pin" pin
            ) spi.cs_pins
          );
        }) config.hardware.raspberry-pi."4".common-overlays.spi-devices;
      };
    })
  ];
}