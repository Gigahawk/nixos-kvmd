{
  description = "Devshell and package definition";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    # HACK: ustreamer 6.11 is pending merge of nixpkgs#308216
    nixpkgs-ustreamer.url = "github:r-ryantm/nixpkgs/auto-update/ustreamer";
    # HACK: wiringpi is really old on nixpkgs
    nixpkgs-wiringpi.url = "github:Gigahawk/nixpkgs/update-wiringpi";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-ustreamer, nixpkgs-wiringpi, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-ustreamer = nixpkgs-ustreamer.legacyPackages.${system};
      pkgs-wiringpi = nixpkgs-wiringpi.legacyPackages.${system};

      kvmd-version = "v3.333";
      kvmd-fan-version = "v0.30";

      python = pkgs.python3;
      pythonPackages = import ./python-requirements.nix;
      pythonWithPackages = python.withPackages pythonPackages;

    in {
      packages = {
        kvmd-src = with import nixpkgs { inherit system; };
        stdenv.mkDerivation rec {
          pname = "kvmd-src";
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
            #pkgs.ustreamer
            pkgs-ustreamer.ustreamer
            pkgs.janus-gateway
            pkgs.glibc
            pkgs.coreutils
            pkgs.sudo
            pkgs.iproute2
            pkgs.ipmitool
            pkgs.iptables
            pkgs.dnsmasq
            pkgs.systemd
          ];

          installPhase = ''
            runHook preInstall

            pushd kvmd-src
            find . -type f -exec install -Dm 755 "{}" "$out/src/{}" \;
            popd

            runHook postInstall
          '';

          patchPhase = ''
            # HACK: patch ctypes.util.find_library calls because nixpkgs#7307 is somehow not fixed yet
            sed -i 's|ctypes.util.find_library("tesseract")|"${pkgs.tesseract}/lib/libtesseract.so.5"|' kvmd-src/kvmd/apps/kvmd/ocr.py
            sed -i 's|ctypes.util.find_library("xkbcommon")|"${pkgs.libxkbcommon}/lib/libxkbcommon.so.0"|' kvmd-src/kvmd/keyboard/printer.py
            sed -i 's|ctypes.util.find_library("c")|"${pkgs.glibc}/lib/libc.so.6"|' kvmd-src/kvmd/libc.py

            # Patch some hardcoded paths in kvmd
            #sed -i 's|/usr/bin/ustreamer|${pkgs.ustreamer}/bin/ustreamer|' kvmd-src/configs/kvmd/main/*.yaml
            sed -i 's|/usr/bin/ustreamer|${pkgs-ustreamer.ustreamer}/bin/ustreamer|' kvmd-src/configs/kvmd/main/*.yaml
            sed -i 's|/usr/bin/sudo|${pkgs.sudo}/bin/sudo|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/sudo|${pkgs.sudo}/bin/sudo|' kvmd-src/kvmd/plugins/msd/otg/__init__.py
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
            sed -i "s|/usr/share/tessdata|${pkgs.tesseract}/share/tessdata|" kvmd-src/kvmd/apps/__init__.py
          '';

          meta = with lib; {
            homepage = "https://github.com/pikvm/kvmd";
            description = "The main PiKVM daemon";
            license = licenses.gpl3;
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
            pkgs-wiringpi.wiringpi
            #pkgs.wiringpi
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
      };
      devShell = pkgs.mkShell {
        inputsFrom = [
        ];
        nativeBuildInputs = [
          pythonWithPackages
          pkgs.libxkbcommon
          pkgs.tesseract
          pkgs.libraspberrypi
          pkgs-ustreamer.ustreamer
          pkgs.janus-gateway
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
              description = mdDoc ''
                Path to the IPMI credentials file

                For more information see:
                https://github.com/pikvm/kvmd/blob/master/configs/kvmd/ipmipasswd
              '';
            };

            vncPasswordFile = mkOption {
              type = types.path;
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
              description = mdDoc ''
                Path to the htpasswd file

                For more information see:
                https://github.com/pikvm/kvmd/blob/master/configs/kvmd/htpasswd
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
          };

          config = mkIf cfg.enable ({
            environment.systemPackages = [
              self.packages.${pkgs.system}.kvmd
              self.packages.${pkgs.system}.kvmd-otg
              self.packages.${pkgs.system}.kvmd-fan
            ];

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

            boot = mkIf cfg.allowMmap ({
              kernelParams = [
                "iomem=relaxed"
                "strict-devmem=0"
              ];
            });

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
                User = defaultUser;
                Group = defaultGroup;
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
              # before = [ "kvmd.service" ];
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
          });
        };
    };
}
