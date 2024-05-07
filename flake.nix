{
  description = "Devshell and package definition";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    pip2nix = {
      url = "github:nix-community/pip2nix";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pip2nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      version = "v3.333";

      #pythonOverrides = pkgs.callPackage ./python-overrides.nix { };
      #customOverrides = pkgs.callPackage ./custom-overrides.nix { };
      #packageOverrides = nixpkgs.lib.composeManyExtensions [ pythonOverrides customOverrides ];
      #python = pkgs.python3.override { inherit packageOverrides; };
      python = pkgs.python3;
      pythonPackages = import ./python-requirements.nix;
      pythonWithPackages = python.withPackages pythonPackages;
    in {
      packages = {
        kvmd-src = with import nixpkgs { inherit system; };
        stdenv.mkDerivation rec {
          pname = "kvmd-src";
          inherit version;
          srcs = [
            (pkgs.fetchFromGitHub {
              name = "kvmd-src";
              owner = "pikvm";
              repo = "kvmd";
              rev = version;
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
            sed -i 's|/usr/bin/ustreamer|${pkgs.ustreamer}/bin/ustreamer|' kvmd-src/configs/kvmd/main/*.yaml
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
      };
      devShell = pkgs.mkShell {
        inputsFrom = [
        ];
        nativeBuildInputs = [
          #pip2nix.packages.${system}.pip2nix.python39
          pythonWithPackages
          pkgs.libxkbcommon
          pkgs.tesseract
          pkgs.libraspberrypi
          pkgs.ustreamer
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
          #usersFile = pkgs.writeText "users.json" (builtins.toJSON cfg.users);
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
          };

          config = mkIf cfg.enable ({
            environment.systemPackages = [
              self.packages.${pkgs.system}.kvmd
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
            # TODO: this should have the correct user permissions
            systemd.tmpfiles.rules = [
              "d /run/kvmd 0777 root root"
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

            #systemd.services.inventree-server = {
            #  description = "InvenTree service";
            #  wantedBy = [ "multi-user.target" ];
            #  environment = {
            #    INVENTREE_CONFIG_FILE = toString cfg.configPath;
            #  };
            #  serviceConfig = {
            #    User = defaultUser;
            #    Group = defaultGroup;
            #    ExecStartPre =
            #      "+${pkgs.writers.writeBash "inventree-setup" ''
            #        echo "Creating config file"
            #        mkdir -p "$(dirname "${toString cfg.configPath}")"
            #        cp ${configFile} ${toString cfg.configPath}

            #        echo "Running database migrations"
            #        ${self.packages.${pkgs.system}.inventree-invoke}/bin/inventree-invoke migrate

            #        echo "Ensuring static files are populated"
            #        ${self.packages.${pkgs.system}.inventree-invoke}/bin/inventree-invoke static

            #        echo "Setting up users"
            #        cat ${usersFile} | \
            #          ${self.packages.${pkgs.system}.inventree-refresh-users}/bin/inventree-refresh-users
            #      ''}";
            #    ExecStart = ''
            #      ${self.packages.${pkgs.system}.inventree-server}/bin/inventree-server -b ${cfg.serverBind}
            #    '';
            #  };
            #};
            #systemd.services.inventree-cluster = {
            #  description = "InvenTree background worker";
            #  wantedBy = [ "multi-user.target" ];
            #  environment = {
            #    INVENTREE_CONFIG_FILE = toString cfg.configPath;
            #  };
            #  serviceConfig = {
            #    User = defaultUser;
            #    Group = defaultGroup;
            #    ExecStart = ''
            #      ${self.packages.${pkgs.system}.inventree-cluster}/bin/inventree-cluster
            #    '';
            #  };
            #};
          });
        };
    };
}
