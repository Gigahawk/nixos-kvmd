{
  description = "Devshell and package definition";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};

      kvmd-version = "v3.333";
      kvmd-fan-version = "v0.30";
      kvmd-packages-version = "c77255958ac96ee51d6e999e1d1950081ed31244";

      helperScript = name: pkgs.writeText "kvmd-helper.py" ''
        import re
        import os
        import sys
        # Hack to allow importing kvmd from script outside of kvmd-src
        sys.path.insert(0, os.getcwd())
        from kvmd.helpers.remount import main
        if __name__ == '__main__':
            sys.argv[0] = '${name}'
            sys.exit(main())
      '';

      # kvmd-oled uses socket.getfqdn() which just returns localhost.
      # Patch it to use socket.gethostname() in this case
      kvmd-oled-wrapper = pkgs.writeText "kvmd-oled-wrapper.py" ''
        import socket
        import importlib
        kvmd_oled = importlib.import_module("kvmd-oled")

        _getfqdn = socket.getfqdn

        def getfqdn():
            out = _getfqdn()
            if "localhost" in out:
                out = socket.gethostname()
            return out

        socket.getfqdn = getfqdn

        if __name__ == "__main__":
            kvmd_oled.main()
      '';

      pythonOverrides = pkgs.callPackage ./python-overrides.nix { };
      python = pkgs.python312.override { packageOverrides = pythonOverrides; };
      pythonPackages = import ./python-requirements.nix;
      pythonWithPackages = python.withPackages pythonPackages;
    in {
      packages = {
        # variant missing some patches to work around circular references
        kvmd-src-unpatched = with import nixpkgs { inherit system; };
        stdenv.mkDerivation rec {
          pname = "kvmd-src-unpatched";
          version = kvmd-version;
          srcs = [
            (pkgs.fetchFromGitHub {
              name = "kvmd-src";
              owner = "pikvm";
              repo = "kvmd";
              rev = kvmd-version;
              hash = "sha256-oWdutzyP36An9Ff+QjWZtahKiXcSboWn+qmymkbKL+A=";
            })
          ];

          sourceRoot = ".";

          propagatedBuildInputs = [
            pythonWithPackages
            pkgs.libxkbcommon
            pkgs.tesseract
            pkgs.libraspberrypi
            pkgs.ustreamer
            pkgs.janus-gateway
            pkgs.glibc
            pkgs.coreutils
            pkgs.sudo
            pkgs.iproute2
            pkgs.ipmitool
            pkgs.iptables
            pkgs.dnsmasq
            pkgs.systemd
            pkgs.v4l-utils
          ];

          installPhase = ''
            runHook preInstall

            pushd kvmd-src
            find . -type f -exec install -Dm 755 "{}" "$out/src/{}" \;
            popd

            runHook postInstall
          '';
          patchPhase = ''
            runHook prePatch

            # HACK: patch ctypes.util.find_library calls because nixpkgs#7307 is somehow not fixed yet
            sed -i 's|ctypes.util.find_library("tesseract")|"${pkgs.tesseract}/lib/libtesseract.so.5"|' kvmd-src/kvmd/apps/kvmd/ocr.py
            sed -i 's|ctypes.util.find_library("xkbcommon")|"${pkgs.libxkbcommon}/lib/libxkbcommon.so.0"|' kvmd-src/kvmd/keyboard/printer.py
            sed -i 's|ctypes.util.find_library("c")|"${pkgs.glibc}/lib/libc.so.6"|' kvmd-src/kvmd/libc.py

            # Patch some hardcoded paths in kvmd
            sed -i 's|/usr/bin/ustreamer|${pkgs.ustreamer}/bin/ustreamer|' kvmd-src/configs/kvmd/main/*.yaml
            sed -i 's|/usr/bin/sudo|/run/wrappers/bin/sudo|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/sudo|/run/wrappers/bin/sudo|' kvmd-src/kvmd/plugins/msd/otg/__init__.py
            sed -i 's|/usr/bin/vcgencmd|${pkgs.libraspberrypi}/bin/vcgencmd|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/janus|${pkgs.janus-gateway}/bin/janus|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/ip|${pkgs.iproute2}/bin/ip|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/systemd-run|${pkgs.systemd}/bin/systemd-run|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/systemctl|${pkgs.systemd}/bin/systemctl|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/sbin/iptables|${pkgs.iptables}/bin/iptables|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/sbin/dnsmasq|${pkgs.dnsmasq}/bin/dnsmasq|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/ipmitool|${pkgs.ipmitool}/bin/ipmitool|' kvmd-src/kvmd/plugins/ugpio/ipmi.py
            sed -i 's|/bin/true|${pkgs.coreutils}/bin/true|' kvmd-src/kvmd/apps/__init__.py
            sed -i "s|/usr/share/kvmd/extras|$out/src/extras|" kvmd-src/kvmd/apps/__init__.py
            sed -i "s|/usr/share/kvmd/keymaps|$out/src/contrib/keymaps|" kvmd-src/kvmd/apps/__init__.py
            sed -i "s|/usr/share/kvmd/configs.default/kvmd/edid|$out/src/configs/kvmd/edid|" kvmd-src/kvmd/apps/edidconf/__init__.py
            sed -i "s|/usr/bin/v4l2-ctl|${pkgs.v4l-utils}/bin/v4l2-ctl|" kvmd-src/kvmd/apps/edidconf/__init__.py
            sed -i "s|/usr/share/tessdata|${pkgs.tesseract}/share/tessdata|" kvmd-src/kvmd/apps/__init__.py

            # HACK: patch remount script to do umount then mount, using remount on an image file doesn't seem to work properly
            sed -i \
              's|subprocess.check_call(\["/bin/mount", "--options", f"remount,{mode}", path\])|subprocess.check_call(["${pkgs.util-linux}/bin/umount", path]);subprocess.check_call(["${pkgs.util-linux}/bin/mount", "--options", f"{mode}", path])|' \
              kvmd-src/kvmd/helpers/remount/__init__.py

            runHook postPatch
          '';

          meta = with lib; {
            homepage = "https://github.com/pikvm/kvmd";
            description = "The main PiKVM daemon";
            license = licenses.gpl3;
            platforms = platforms.all;
          };
        };
        kvmd-src = self.packages.${system}.kvmd-src-unpatched.overrideAttrs (old: {
          pname = "kvmd-src";
          postPatch = ''
            # Patches requiring references to downstream kvmd packages
            sed -i 's|/usr/bin/kvmd-helper-otgmsd-remount|${self.packages.${system}.kvmd-helper-otgmsd-remount}/bin/kvmd-helper-otgmsd-remount|' kvmd-src/kvmd/plugins/msd/otg/__init__.py
          '';
        });
        kvmd-packages-src = with import nixpkgs { inherit system; };
        stdenv.mkDerivation rec {
          pname = "kvmd-packages-src";
          version = kvmd-packages-version;
          srcs = [
            (pkgs.fetchFromGitHub {
              name = "kvmd-packages-src";
              owner = "pikvm";
              repo = "packages";
              rev = kvmd-packages-version;
              hash = "sha256-T6GeJjmxnvK+Gt6P2SKdr0J5upXOG0a4ocTWTohMyUw=";
            })
          ];

          sourceRoot = ".";

          propagatedBuildInputs = [
            pythonWithPackages
          ];

          installPhase = ''
            runHook preInstall

            pushd kvmd-packages-src
            find . -type f -exec install -Dm 755 "{}" "$out/src/{}" \;
            install -Dm 755 "${kvmd-oled-wrapper}" "$out/src/packages/kvmd-oled/kvmd-oled-wrapper.py"
            popd

            runHook postInstall
          '';
          patchPhase = ''
            runHook prePatch

            # Patch hardcoded paths in kvmd-oled
            sed -i "s|/usr/share/kvmd-oled/ProggySquare.ttf|$out/src/packages/kvmd-oled/ProggySquare.ttf|" kvmd-packages-src/packages/kvmd-oled/kvmd-oled.py

            # Patch kvmd-oled to display something when it is killed
            # The reboot and shutdown services provided by pikvm don't seem to work properly
            sed -i 's|stop_reason = ""|stop_reason = "Halting..."|' kvmd-packages-src/packages/kvmd-oled/kvmd-oled.py

            runHook postPatch
          '';

          meta = with lib; {
            homepage = "https://github.com/pikvm/packages";
            description = "PiKVM Packages";
            # Doesn't seem to have a license?
            #license = licenses.gpl3;
            platforms = platforms.all;
          };
        };
        kvmd-fan = with import nixpkgs { inherit system; };
        stdenv.mkDerivation rec {
          pname = "kvmd-fan";
          version = kvmd-fan-version;
          srcs = [
            (pkgs.fetchFromGitHub {
              name = "kvmd-fan";
              owner = "pikvm";
              repo = "kvmd-fan";
              rev = kvmd-fan-version;
              hash = "sha256-jKoiIl0n19bL0xzGjwNJCKnqwBlSBQ774X89ETG5S1c=";
            })
          ];

          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          buildInputs = [
            pkgs.wiringpi
            pkgs.libgpiod
            pkgs.iniparser
            pkgs.libmicrohttpd
          ];

          installPhase = ''
            make install PREFIX="" DESTDIR=$out
          '';

          meta = with lib; {
            homepage = "https://github.com/pikvm/kvmd-fan";
            description = "A small fan controller daemon for PiKVM";
            license = licenses.gpl3;
            platforms = platforms.all;
          };
        };
        kvmd = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd";

          runtimeInputs = self.packages.${system}.kvmd-src.propagatedBuildInputs;

          text = ''
          KVMD_SRC=${self.packages.${system}.kvmd-src}/src
          pushd $KVMD_SRC
          python -m kvmd.apps.kvmd "$@"
          popd
          '';
        };
        kvmd-otg = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd-otg";

          runtimeInputs = self.packages.${system}.kvmd-src.propagatedBuildInputs;

          text = ''
          KVMD_SRC=${self.packages.${system}.kvmd-src}/src
          pushd $KVMD_SRC
          python -m kvmd.apps.otg "$@"
          popd
          '';
        };
        kvmd-cleanup = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd-cleanup";

          runtimeInputs = self.packages.${system}.kvmd-src.propagatedBuildInputs;

          text = ''
          KVMD_SRC=${self.packages.${system}.kvmd-src}/src
          pushd $KVMD_SRC
          python -m kvmd.apps.cleanup "$@"
          popd
          '';
        };
        kvmd-helper-otgmsd-remount = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd-helper-otgmsd-remount";

          runtimeInputs = self.packages.${system}.kvmd-src-unpatched.propagatedBuildInputs;

          text = ''
          KVMD_SRC=${self.packages.${system}.kvmd-src-unpatched}/src
          pushd $KVMD_SRC
          python ${helperScript name} "$@"
          popd
          '';
        };
        kvmd-edidconf = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd-edidconf";

          runtimeInputs = self.packages.${system}.kvmd-src.propagatedBuildInputs;

          text = ''
          KVMD_SRC=${self.packages.${system}.kvmd-src}/src
          pushd $KVMD_SRC
          python -m kvmd.apps.edidconf "$@"
          popd
          '';
        };
        kvmd-oled = with import nixpkgs { inherit system; };
        pkgs.writeShellApplication rec {
          name = "kvmd-oled";

          runtimeInputs = self.packages.${system}.kvmd-packages-src.propagatedBuildInputs;

          text = ''
          PACKAGES_SRC=${self.packages.${system}.kvmd-packages-src}/src
          pushd $PACKAGES_SRC/packages/kvmd-oled
          python kvmd-oled-wrapper.py "$@"
          popd
          '';
        };
      };
      devShell = pkgs.mkShell {
        nativeBuildInputs = [
          pythonWithPackages
          pkgs.libxkbcommon
          pkgs.tesseract
          pkgs.libraspberrypi
          pkgs.ustreamer
          pkgs.janus-gateway
          self.packages.${system}.kvmd-edidconf
        ];
      };
    }) // {
      nixosModule = { lib, pkgs, config, ... }:
        with lib;
        let
          cfg = config.services.kvmd;
          settingsFormat = pkgs.formats.json { };
          defaultUser = "kvmd";
          defaultGroup = defaultUser;
          overrideFile = pkgs.writeText "override.yaml" (builtins.toJSON cfg.overrides);
        in
        {
          options.services.kvmd = {
            enable = mkEnableOption
              (lib.mdDoc "The main PiKVM daemon");

            hostName = mkOption {
              type = types.str;
              default = "_";
              description = mdDoc ''
                FQDN for the kvmd instance
              '';
            };

            allowMmap = mkEnableOption
              (lib.mdDoc ''
                Set iomem=relaxed and strict-devmem=0.
                Required for GPIO fan access on Raspberry Pi 4
              '');

            ipmiPasswordFile = mkOption {
              type = types.path;
              default = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/ipmipasswd;
              description = mdDoc ''
                Path to the IPMI credentials file

                For more information see:
                https://github.com/pikvm/kvmd/blob/master/configs/kvmd/ipmipasswd
              '';
            };

            vncPasswordFile = mkOption {
              type = types.path;
              default = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/vncpasswd;
              description = mdDoc ''
                Path to the VNCAuth credentials file

                For more information see:
                https://github.com/pikvm/kvmd/blob/master/configs/kvmd/vncpasswd
              '';
            };

            vncSslKeyFile = mkOption {
              type = types.path;
              description = mdDoc ''
                Path to an SSL key for the VNC server
              '';
            };

            vncSslCertFile = mkOption {
              type = types.path;
              description = mdDoc ''
                Path to an SSL certificate for the VNC server
              '';
            };

            htPasswordFile = mkOption {
              type = types.path;
              default = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/htpasswd;
              description = mdDoc ''
                Path to the htpasswd file

                For more information see:
                https://github.com/pikvm/kvmd/blob/master/configs/kvmd/htpasswd
              '';
            };

            totpSecretFile = mkOption {
              type = types.path;
              default = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/totp.secret;
              description = mdDoc ''
                Path to a file containing a base32 encoded TOTP secret
              '';
            };

            overrides = mkOption {
              type = types.attrs;
              default = {};
              description = lib.mdDoc ''
                Config overrides
              '';
            };

            #user = mkOption {
            #  type = types.str;
            #  default = defaultUser;
            #  example = "yourUser";
            #  description = mdDoc ''
            #    The user to run InvenTree as.
            #    By default, a user named `${defaultUser}` will be created whose home
            #    directory is [dataDir](#opt-services.inventree.dataDir).
            #  '';
            #};

            #group = mkOption {
            #  type = types.str;
            #  default = defaultGroup;
            #  example = "yourGroup";
            #  description = mdDoc ''
            #    The group to run Syncthing under.
            #    By default, a group named `${defaultGroup}` will be created.
            #  '';
            #};

            baseConfig = mkOption {
              type = with types; either str path;
              default = "v4plus-hdmi-rpi4.yaml";
              apply = val: if builtins.isPath val then val else self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/main/${val};
              description = lib.mdDoc ''
                The base config file to use for kvmd
              '';
            };

            fanArgs = mkOption {
              type = types.str;
              default = "";
              description = lib.mdDoc ''
                Arguments to pass to kvmd-fan on startup
              '';
            };

            fanConfig = mkOption {
              type = with types; either str path;
              default = "v4plus-hdmi.ini";
              apply = val: if builtins.isPath val then val else self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/fan/${val};
              description = lib.mdDoc ''
                The config file to use for kvmd fan
              '';
            };

            edidConfig = mkOption {
              type = with types; either str path;
              default = "v4plus-hdmi.hex";
              apply = val: if builtins.isPath val then val else self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/edid/${val};
              description = lib.mdDoc ''
                The EDID hex file to use for HDMI to CSI adapters
              '';
            };

            udevRules = mkOption {
              type = with types; either str path;
              default = "v4plus-hdmi-rpi4.rules";
              apply = val: if builtins.isPath val then val else self.packages.${pkgs.system}.kvmd-src + /src/configs/os/udev/${val};
              description = lib.mdDoc ''
                The config file to use for kvmd fan
              '';
            };

            createMsdImage = mkEnableOption (
              lib.mdDoc ''
                Create an ext4 image file for MSD emulation

                IMPORTANT: Requires rebuilding the SD image
                (must have an sd-image module enabled)
              '');
            msdImageSize = mkOption {
              type = types.str;
              default = "4G";
              description = lib.mdDoc ''
                Size of the image for MSD emulation
              '';
            };
            msdImagePath = mkOption {
              type = types.str;
              default = "/media/msd.img";
              description = lib.mdDoc ''
                Path to generate the image file at
              '';
            };
            msdImageDepends = mkOption {
              type = types.listOf types.str;
              default = [ "/" ];
              description = lib.mdDoc ''
                Filesystems to mount before mounting the MSD emulation image
              '';
            };

            enableOled = mkEnableOption (
              lib.mdDoc ''
                Enable support for showing device info on an SSD1306 I2C screen

                Should be connected to I2C1.
              '');
            oledHeight = lib.mkOption {
              type = lib.types.enum [ 32 64 ];
              default = 32;
              description = ''
                Display height in pixels
              '';
            };
            oledRotation = lib.mkOption {
              type = lib.types.enum [ 0 1 2 3 ];
              default = 0;
              description = ''
                Display orientation (multiply by 90 degrees)
              '';
            };
            oledSplash = mkOption {
              type = with types; either str path;
              default = "pikvm.ppm";
              apply = val: if builtins.isPath val then val else self.packages.${pkgs.system}.kvmd-packages-src + /src/packages/kvmd-oled/${val};
              description = lib.mdDoc ''
                The image to use for the splash screen
              '';
            };
          };

          config = mkIf cfg.enable (
            mkMerge [
              {
                environment.systemPackages = [
                  self.packages.${pkgs.system}.kvmd
                  self.packages.${pkgs.system}.kvmd-otg
                  self.packages.${pkgs.system}.kvmd-fan
                  self.packages.${pkgs.system}.kvmd-edidconf
                ];

                services.udev = {
                  enable = true;
                  extraRules = lib.strings.concatLines [
                    # Seems like this has something to do with allowing access
                    # to an RP2040 acting as an HID emulator
                    (builtins.readFile (self.packages.${pkgs.system}.kvmd-src + /src/configs/os/udev/common.rules))
                    # User selected set of rules
                    (builtins.readFile cfg.udevRules)
                    # Allow video user to access RPi VideoCore interface
                    ''KERNEL=="vchiq", GROUP="video", MODE="0660"''
                    # Allow GPIO to be controlled by users in gpiod group
                    ''SUBSYSTEM=="gpio", KERNEL=="gpiochip[0-4]", GROUP="gpiod", MODE="0660"''
                  ];
                };

                users.users.${defaultUser} = {
                  group = defaultGroup;
                  # Is this important?
                  #uid = config.ids.uids.inventree;
                  # Seems to be required with no uid set
                  isSystemUser = true;
                  description = "kvmd daemon user";
                };

                users.groups.${defaultGroup} = {
                  # Is this important?
                  #gid = config.ids.gids.inventree;
                  # Allow nginx to read data
                  members = [ "nginx" ];
                };

                # Add kvmd to groups for hardware access
                # TODO: gpiod isn't a standard group on NixOS,
                # is there a more idiomatic way to do this?
                users.groups.gpiod = {
                  members = [ "kvmd" ];
                };
                users.groups.video = {
                  members = [ "kvmd" ];
                };

                boot = {
                  # Enable USB emulation
                  kernelModules = [ "libcomposite" ];
                  kernelParams = mkIf cfg.allowMmap ([
                    "iomem=relaxed"
                    "strict-devmem=0"
                  ]);
                };

                environment.etc = {
                  "kvmd/main.yaml" = {
                    source = cfg.baseConfig;
                  };
                  "kvmd/override.yaml" = {
                    source = overrideFile;
                  };
                  # TODO: is there a way to just have a blank folder?
                  "kvmd/override.d/.ignore"= {
                    text = "";
                  };
                  "kvmd/fan.ini" = {
                    source = cfg.fanConfig;
                  };
                  "kvmd/logging.yaml" = {
                    source = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/logging.yaml;
                  };
                  "kvmd/auth.yaml" = {
                    source = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/auth.yaml;
                  };
                  "kvmd/meta.yaml" = {
                    source = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/meta.yaml;
                  };
                  "kvmd/web.css" = {
                    source = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/web.css;
                  };
                  "kvmd/ipmipasswd" = {
                    source = cfg.ipmiPasswordFile;
                  };
                  "kvmd/htpasswd" = {
                    source = cfg.htPasswordFile;
                  };
                  "kvmd/totp.secret" = {
                    source = cfg.totpSecretFile;
                  };
                  "kvmd/vncpasswd" = {
                    source = cfg.vncPasswordFile;
                  };
                  "kvmd/vnc/ssl/server.crt" = {
                    source = cfg.vncSslCertFile;
                  };
                  "kvmd/vnc/ssl/server.key" = {
                    source = cfg.vncSslKeyFile;
                  };
                };

                security.sudo = {
                  enable = true;
                  extraRules = [{
                    commands = [
                      {
                        command = "${self.packages.${pkgs.system}.kvmd-helper-otgmsd-remount}/bin/kvmd-helper-otgmsd-remount";
                        options = [ "NOPASSWD" ];
                      }
                    ];
                    users = [ "kvmd" ];
                    groups = [ "kvmd" ];
                  }];
                };

                systemd.tmpfiles.rules = [
                  # Execute bit is required for some reason?
                  "d /run/kvmd 0770 kvmd kvmd"
                ];

                services.nginx = {
                  enable = true;
                  upstreams = {
                    kvmd.servers = {
                      "unix:/run/kvmd/kvmd.sock" = {
                        fail_timeout = "0s";
                        max_fails = 0;
                      };
                    };
                    ustreamer.servers = {
                      "unix:/run/kvmd/ustreamer.sock" = {
                        fail_timeout = "0s";
                        max_fails = 0;
                      };
                    };
                  };
                  virtualHosts."${cfg.hostName}" = {
                    extraConfig = ''
                      absolute_redirect off;
                      index index.html;
                      auth_request /auth_check;
                    '';
                    locations = {
                      "= /auth_check" = {
                        extraConfig = ''
                          internal;
                          proxy_pass http://kvmd/auth/check;
                          proxy_pass_request_body off;
                          proxy_set_header Content-Length "";
                          auth_request off;
                        '';
                      };
                      "/" = {
                        root = self.packages.${pkgs.system}.kvmd-src + /src/web;
                        extraConfig = ''
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-login.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nocache.conf};
                        '';
                      };
                      "@login" = {
                        return = "302 /login";
                      };
                      "/login" = {
                        root = self.packages.${pkgs.system}.kvmd-src + /src/web;
                        extraConfig = ''
                          auth_request off;
                        '';
                      };
                      "/share" = {
                        root = self.packages.${pkgs.system}.kvmd-src + /src/web;
                        extraConfig = ''
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nocache.conf};
                          auth_request off;
                        '';
                      };
                      "= /share/css/user.css" = {
                        alias = "/etc/kvmd/web.css";
                        extraConfig = ''
                          auth_request off;
                        '';
                      };
                      "= /favicon.ico" = {
                        alias = self.packages.${pkgs.system}.kvmd-src + /src/web/favicon.ico;
                        extraConfig = ''
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nocache.conf};
                          auth_request off;
                        '';
                      };
                      "= /robots.txt" = {
                        alias = self.packages.${pkgs.system}.kvmd-src + /src/web/robots.txt;
                        extraConfig = ''
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nocache.conf};
                          auth_request off;
                        '';
                      };
                      "/api/ws" = {
                        extraConfig = ''
                          rewrite ^/api/ws$ /ws break;
                          rewrite ^/api/ws\?(.*)$ /ws?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-websocket.conf};
                          auth_request off;
                        '';
                      };
                      "/api/hid/print" = {
                        extraConfig = ''
                          rewrite ^/api/hid/print$ /hid/print break;
                          rewrite ^/api/hid/print\?(.*)$ /hid/print?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-bigpost.conf};
                          auth_request off;
                        '';
                      };
                      "/api/msd/read" = {
                        extraConfig = ''
                          rewrite ^/api/msd/read$ /msd/read break;
                          rewrite ^/api/msd/read\?(.*)$ /msd/read?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nobuffering.conf};
                          proxy_read_timeout 7d;
                          auth_request off;
                        '';
                      };
                      "/api/msd/write_remote" = {
                        extraConfig = ''
                          rewrite ^/api/msd/write_remote$ /msd/write_remote break;
                          rewrite ^/api/msd/write_remote\?(.*)$ /msd/write_remote?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nobuffering.conf};
                          proxy_read_timeout 7d;
                          auth_request off;
                        '';
                      };
                      "/api/msd/write" = {
                        extraConfig = ''
                          rewrite ^/api/msd/write$ /msd/write break;
                          rewrite ^/api/msd/write\?(.*)$ /msd/write?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-bigpost.conf};
                          auth_request off;
                        '';
                      };
                      "/api/log" = {
                        extraConfig = ''
                          rewrite ^/api/log$ /log break;
                          rewrite ^/api/log\?(.*)$ /log?$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nobuffering.conf};
                          proxy_read_timeout 7d;
                          auth_request off;
                        '';
                      };
                      "/api" = {
                        extraConfig = ''
                          rewrite ^/api$ / break;
                          rewrite ^/api/(.*)$ /$1 break;
                          proxy_pass http://kvmd;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          auth_request off;
                        '';
                      };
                      "/streamer" = {
                        extraConfig = ''
                          rewrite ^/streamer$ / break;
                          rewrite ^/streamer\?(.*)$ ?$1 break;
                          rewrite ^/streamer/(.*)$ /$1 break;
                          proxy_pass http://ustreamer;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nobuffering.conf};
                        '';
                      };
                      "/redfish" = {
                        extraConfig = ''
                          rewrite ^/streamer$ / break;
                          rewrite ^/streamer\?(.*)$ ?$1 break;
                          rewrite ^/streamer/(.*)$ /$1 break;
                          proxy_pass http://ustreamer;
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-proxy.conf};
                          include ${self.packages.${pkgs.system}.kvmd-src + /src/configs/nginx/loc-nobuffering.conf};
                        '';
                      };
                    };
                  };
                };

                # This is needed for nginx to be able to read other processes
                # directories in `/run`. Else it will fail with (13: Permission denied)
                systemd.services.nginx.serviceConfig.ProtectHome = false;

                systemd.services.kvmd-fan = {
                  description = "PiKVM - A small fan controller daemon";
                  after = [ "systemd-modules-load.service" ];
                  serviceConfig = {
                    # kvmd-otg has to run as root to access /dev/mem
                    User = "root";
                    Group = "root";
                    Type = "simple";
                    Restart = "always";
                    RestartSec = 3;
                    ExecStart = ''
                      ${self.packages.${pkgs.system}.kvmd-fan}/bin/kvmd-fan --config=/etc/kvmd/fan.ini ${cfg.fanArgs}
                    '';
                    TimeoutStopSec = 3;
                  };
                  wantedBy = [ "multi-user.target" ];
                };
                systemd.services.kvmd-otg = {
                  description = "PiKVM - OTG setup";
                  after = [ "systemd-modules-load.service" ];
                  before = [ "kvmd.service" ];
                  serviceConfig = {
                    # kvmd-otg has to run as root to modify sysfs
                    User = "root";
                    Group = "root";
                    Type = "oneshot";
                    ExecStart = ''
                      ${self.packages.${pkgs.system}.kvmd-otg}/bin/kvmd-otg start
                    '';
                    ExecStop = ''
                      ${self.packages.${pkgs.system}.kvmd-otg}/bin/kvmd-otg stop
                    '';
                    RemainAfterExit = true;
                  };
                  wantedBy = [ "multi-user.target" ];
                };
                systemd.services.kvmd-tc358743 = {
                  description = "PiKVM - EDID loader for TC358743";
                  # What is dev-kvmd\x2dvideo.device?
                  wants = [
                    # "dev-kvmd\x2dvideo.device"
                  ];
                  after = [
                    # "dev-kvmd\x2dvideo.device"
                    "systemd-modules-load.service"
                  ];
                  before = [
                    "kvmd.service"
                    # TODO: support pass through?
                    # "kvmd-pass.service"
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    Restart = "on-failure";
                    RestartSec = 5;
                    ExecStart = ''
                      ${pkgs.v4l-utils}/bin/v4l2-ctl --device=/dev/kvmd-video --set-edid=file=${cfg.edidConfig} --info-edid
                    '';
                    ExecStop= ''
                      ${pkgs.v4l-utils}/bin/v4l2-ctl --device=/dev/kvmd-video --clear-edid
                    '';
                    RemainAfterExit = true;
                  };
                  wantedBy = [ "multi-user.target" ];
                };
                systemd.services.kvmd = {
                  description = "PiKVM - The main daemon";
                  after = [
                    "network.target"
                    "network-online.target"
                    "nss-lookup.target"
                  ];
                  serviceConfig = {
                    User = "kvmd";
                    Group = "kvmd";
                    Type = "simple";
                    Restart = "always";
                    RestartSec = 3;
                    AmbientCapabilities = "CAP_NET_RAW";

                    ExecStart = ''
                      ${self.packages.${pkgs.system}.kvmd}/bin/kvmd --run
                    '';
                    ExecStopPost = ''
                      ${self.packages.${pkgs.system}.kvmd-cleanup}/bin/kvmd-cleanup --run
                    '';
                    TimeoutStopSec = 10;
                    KillMode = "mixed";
                  };
                  wantedBy = [ "multi-user.target" ];
                };
              }
              (mkIf cfg.createMsdImage {
                sdImage.populateRootCommands = ''
                  echo "Creating kvmd USB MSD image file"
                  mkdir -p ./files/$(${pkgs.coreutils}/bin/dirname ${cfg.msdImagePath})
                  ${pkgs.coreutils}/bin/truncate --size=${cfg.msdImageSize} ./files/${cfg.msdImagePath}
                  ${pkgs.e2fsprogs}/bin/mkfs.ext4 ./files/media/msd.img
                '';
                fileSystems = {
                  "/var/lib/kvmd/msd" = {
                    depends = cfg.msdImageDepends;
                    device = cfg.msdImagePath;
                    fsType = "ext4";
                    options = [
                      "nodev"
                      "nosuid"
                      "noexec"
                      "ro"
                      "errors=remount-ro"
                      "X-kvmd.otgmsd-user=kvmd"
                    ];
                  };
                };
              })
              (mkIf cfg.enableOled {
                systemd.services.kvmd-oled = {
                  description = "PiKVM - A small OLED daemon";
                  after = [ "systemd-modules-load.service" ];
                  unitConfig = {
                    ConditionPathExists = "/dev/i2c-1";
                  };
                  serviceConfig = {
                    Type = "simple";
                    Restart = "always";
                    RestartSec = 3;
                    ExecStartPre = ''
                      ${self.packages.${pkgs.system}.kvmd-oled}/bin/kvmd-oled --rotate=${toString cfg.oledRotation} --height=${toString cfg.oledHeight} --interval=3 --clear-on-exit --image=${cfg.oledSplash}
                    '';
                    ExecStart = ''
                      ${self.packages.${pkgs.system}.kvmd-oled}/bin/kvmd-oled --rotate=${toString cfg.oledRotation} --height=${toString cfg.oledHeight}
                    '';
                    TimeoutStopSec = 3;
                  };
                  wantedBy = [ "multi-user.target" ];
                };
              })
            ]
          );
        };
    };
}
