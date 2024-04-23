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
          #configFile = pkgs.writeText "config.yaml" (builtins.toJSON cfg.config);
          #usersFile = pkgs.writeText "users.json" (builtins.toJSON cfg.users);
        in
        {
          options.services.kvmd = {
            enable = mkEnableOption
              (lib.mdDoc "The main PiKVM daemon");

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
              type = types.str;
              default = "v4plus-hdmi-rpi4.yaml";
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
                source = self.packages.${pkgs.system}.kvmd-src + /src/configs/kvmd/main/${cfg.baseConfig};
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
