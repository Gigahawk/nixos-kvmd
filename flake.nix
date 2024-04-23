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


            sed -i 's|/usr/bin/vcgencmd|${pkgs.libraspberrypi}/bin/vcgencmd|' kvmd-src/kvmd/apps/__init__.py
            sed -i 's|/usr/bin/janus|${pkgs.janus-gateway}/bin/janus|' kvmd-src/kvmd/apps/__init__.py

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
          python -m kvmd.apps.kvmd
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
      #nixosModule = { lib, pkgs, config, ... }:
      #  with lib;
      #  let
      #    cfg = config.services.inventree;
      #    settingsFormat = pkgs.formats.json { };
      #    defaultUser = "inventree";
      #    defaultGroup = defaultUser;
      #    configFile = pkgs.writeText "config.yaml" (builtins.toJSON cfg.config);
      #    usersFile = pkgs.writeText "users.json" (builtins.toJSON cfg.users);
      #  in
      #  {
      #    options.services.inventree = {
      #      enable = mkEnableOption
      #        (lib.mdDoc "Open Source Inventory Management System");

      #      #user = mkOption {
      #      #  type = types.str;
      #      #  default = defaultUser;
      #      #  example = "yourUser";
      #      #  description = mdDoc ''
      #      #    The user to run InvenTree as.
      #      #    By default, a user named `${defaultUser}` will be created whose home
      #      #    directory is [dataDir](#opt-services.inventree.dataDir).
      #      #  '';
      #      #};

      #      #group = mkOption {
      #      #  type = types.str;
      #      #  default = defaultGroup;
      #      #  example = "yourGroup";
      #      #  description = mdDoc ''
      #      #    The group to run Syncthing under.
      #      #    By default, a group named `${defaultGroup}` will be created.
      #      #  '';
      #      #};

      #      serverBind = mkOption {
      #        type = types.str;
      #        default = "127.0.0.1:8000";
      #        example = "0.0.0.0:1337";
      #        description = lib.mdDoc ''
      #          The address and port the server will bind to.
      #          (nginx should point to this address if running in production mode)
      #        '';
      #      };

      #      dataDir = mkOption {
      #        type = types.str;
      #        default = "/var/lib/inventree";
      #        example = "/home/yourUser";
      #        description = lib.mdDoc ''
      #          The default path for all inventree data.
      #        '';
      #      };

      #      configPath = mkOption {
      #        type = types.str;
      #        default = cfg.dataDir + "/config.yaml";
      #        description = lib.mdDoc ''
      #          Path to config.yaml (automatically created)
      #        '';
      #      };

      #      config = mkOption {
      #        type = types.attrs;
      #        default = {};
      #        description = lib.mdDoc ''
      #          Config options, see https://docs.inventree.org/en/stable/start/config/
      #          for details
      #        '';
      #      };

      #      users = mkOption {
      #        default = {};
      #        description = mdDoc ''
      #          Users which should be present on the InvenTree server
      #        '';
      #        example = {
      #          admin = {
      #            email = "admin@localhost";
      #            is_superuser = true;
      #            password_file = /path/to/passwordfile;
      #          };
      #        };
      #        type = types.attrsOf (types.submodule ({ name, ... }: {
      #          freeformType = settingsFormat.type;
      #          options = {
      #            name = mkOption {
      #              type = types.str;
      #              default = name;
      #              description = lib.mdDoc ''
      #                The name of the user
      #              '';
      #            };

      #            password_file = mkOption {
      #              type = types.path;
      #              description = lib.mdDoc ''
      #                The path to the password file for the user
      #              '';
      #            };

      #            is_superuser = mkOption {
      #              type = types.bool;
      #              default = false;
      #              description = lib.mdDoc ''
      #                Set to true to create the account as a superuser
      #              '';
      #            };
      #          };
      #        }));
      #      };
      #    };

      #    config = mkIf cfg.enable ({
      #      environment.systemPackages = [
      #        self.packages.${pkgs.system}.inventree-invoke
      #      ];

      #      users.users.${defaultUser} = {
      #        group = defaultGroup;
      #        # Is this important?
      #        #uid = config.ids.uids.inventree;
      #        # Seems to be required with no uid set
      #        isSystemUser = true;
      #        description = "InvenTree daemon user";
      #      };

      #      users.groups.${defaultGroup} = {
      #        # Is this important?
      #        #gid = config.ids.gids.inventree;
      #      };

      #      systemd.services.inventree-server = {
      #        description = "InvenTree service";
      #        wantedBy = [ "multi-user.target" ];
      #        environment = {
      #          INVENTREE_CONFIG_FILE = toString cfg.configPath;
      #        };
      #        serviceConfig = {
      #          User = defaultUser;
      #          Group = defaultGroup;
      #          ExecStartPre =
      #            "+${pkgs.writers.writeBash "inventree-setup" ''
      #              echo "Creating config file"
      #              mkdir -p "$(dirname "${toString cfg.configPath}")"
      #              cp ${configFile} ${toString cfg.configPath}

      #              echo "Running database migrations"
      #              ${self.packages.${pkgs.system}.inventree-invoke}/bin/inventree-invoke migrate

      #              echo "Ensuring static files are populated"
      #              ${self.packages.${pkgs.system}.inventree-invoke}/bin/inventree-invoke static

      #              echo "Setting up users"
      #              cat ${usersFile} | \
      #                ${self.packages.${pkgs.system}.inventree-refresh-users}/bin/inventree-refresh-users
      #            ''}";
      #          ExecStart = ''
      #            ${self.packages.${pkgs.system}.inventree-server}/bin/inventree-server -b ${cfg.serverBind}
      #          '';
      #        };
      #      };
      #      systemd.services.inventree-cluster = {
      #        description = "InvenTree background worker";
      #        wantedBy = [ "multi-user.target" ];
      #        environment = {
      #          INVENTREE_CONFIG_FILE = toString cfg.configPath;
      #        };
      #        serviceConfig = {
      #          User = defaultUser;
      #          Group = defaultGroup;
      #          ExecStart = ''
      #            ${self.packages.${pkgs.system}.inventree-cluster}/bin/inventree-cluster
      #          '';
      #        };
      #      };
      #    });
      #  };
    };
}
