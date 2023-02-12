{config, pkgs, options, lib, ...}@args:
let

  eachInstance = config.services.papermc-server;
  instanceOpts = args: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 25565;
        example = 25565;
        description = ''
          servert port
        '';
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "papermc";
        example = "papermc";
        description = ''
          user name PREFIX which will run service. Each instance will have it's own user
        '';
      };
      plugins = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "list of string URLs to download plugins from";
        example = ''
          {
            "floodgate-spigot.jar" = "https://ci.opencollab.dev/job/GeyserMC/job/Floodgate/job/master/lastSuccessfulBuild/artifact/spigot/build/libs/floodgate-spigot.jar";
            "Geyser-Spigot.jar" = "https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/build/libs/Geyser-Spigot.jar";
            "ViaVersion-4.5.1.jar" = "https://ci.viaversion.com/job/ViaVersion/664/artifact/build/libs/ViaVersion-4.5.1.jar";
          }
        '';
      };
      extraCmdArgs = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = ''
          -Xmx2G
        '';
      };
      extraConfig = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = ''
        '';
      };
      nonDefaultConfig = lib.mkOption {
        type = lib.types.attrs;
        default = {
          online-mode="false";
          enforce-secure-profile="false";
          white-list="true";
        };
        example = ''
          {
            online-mode="false";
            enforce-secure-profile="false";
            white-list="true";
          }
        '';
      };
    };
  };
in
{
  options.services.papermc-server = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instanceOpts);
    default = {};
    description = "One or more papermc instances";
    example = {
      "25656" = {
        port = 25565;
      };
    };
  };

  config = lib.mkIf (eachInstance != {}) {
    environment.systemPackages = [ pkgs.papermc ];
    networking.firewall.allowedUDPPorts = [ 19132];
    networking.firewall.allowedTCPPorts = lib.mapAttrsToList (name: cfg: cfg.port) eachInstance;
    # create user
    systemd.services = ( lib.mapAttrs' (name: cfg: lib.nameValuePair "papermc-${name}" (
      let
        instanceDir = "/var/lib/papermc-${name}";
      in {
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-setup.service"
        ];
        requires = [
          "network-setup.service"
          ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          StartLimitIntervalSec = 10;
          StartLimitBurst = 10;
        };
        path = with pkgs; [
          papermc
          wget
          gnused
          bashInteractive
          screen
          curl
          sudo
        ];
        script =
          let
            rendered_sed = lib.foldl' (acc: item: acc + item) "" (lib.mapAttrsToList (cfgName: cfgValue:
              ("sed -i \'s/${cfgName}=.*$/${cfgName}=${cfgValue}\/' server.properties;")
            ) cfg.nonDefaultConfig);
            rendered_plugins = lib.foldl' (acc: item: acc + item) "" (lib.mapAttrsToList (pluginFile: pluginURL: ''
                if [ ! -e "${pluginFile}" ]; then
                  wget '${pluginURL}' -O "${pluginFile}"
                fi
              '') cfg.plugins
            );
          in ''
            set -ex

            # init server
            if [ ! -e "${instanceDir}/inited" ]; then
              rm -rf "${instanceDir}"
              mkdir -p "${instanceDir}"
              chown "${cfg.username}${name}" "${instanceDir}"
              cd "${instanceDir}"

              # initial start
              sudo -u "${cfg.username}${name}" minecraft-server ${cfg.extraCmdArgs} || true # will fail to confirm eula

              # replace config options
              ${rendered_sed}
              # agree with eula and adjust port
              sed -i "s/eula=false/eula=true/" eula.txt

              # inited
              touch "${instanceDir}/inited"
            fi
            cd "${instanceDir}"
            sed -i "s/server-port=.*$/server-port=${toString cfg.port}/" server.properties

            # download plugins
            mkdir -p plugins
            chown "${cfg.username}${name}" "${instanceDir}/plugins"
            cd plugins
            ${rendered_plugins}
            cd ..


            # start server
            cd /var/lib/papermc-${name}
            sudo -u "${cfg.username}${name}" screen -D -m -S minecraft minecraft-server ${cfg.extraCmdArgs}
        '';
      })) eachInstance
    );
    users.users = lib.mapAttrs' (name: cfg: lib.nameValuePair "${cfg.username}${name}" (
      { isNormalUser = true;
      }
      )
    ) eachInstance;
    
  };
}
