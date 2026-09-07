{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.windscribe;
  # Note: To use the GUI or CLI without running as root, users must be in the "windscribe" group:
  # users.users.<name>.extraGroups = [ "windscribe" ];
  platformTag = if pkgs.stdenv.hostPlatform.isAarch64 then "linux_deb_arm64" else "linux_deb_x64";
in
{
  options.services.windscribe = {
    enable = lib.mkEnableOption ''
      Windscribe VPN client daemon and system integration.

      Note: Users must be in the "windscribe" group to communicate with the helper socket:
      `users.users.<name>.extraGroups = [ "windscribe" ];`
    '';

    package = lib.mkPackageOption pkgs "windscribe" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.windscribe = { };

    users.users.windscribe = {
      isSystemUser = true;
      group = "windscribe";
      description = "Windscribe daemon user";
      home = "/var/lib/windscribe";
      createHome = true;
    };

    systemd.tmpfiles.rules = [
      "d /var/run/windscribe 0775 root windscribe -"
      "d /var/log/windscribe 0775 root windscribe -"
      "d /var/lib/windscribe 0775 root windscribe -"
      "d /etc/windscribe 0755 root root -"
      "L+ /opt/windscribe - - - - ${cfg.package}/opt/windscribe"
      "C+ /etc/windscribe/platform - - - - ${pkgs.writeText "platform" "${platformTag}\n"}"
      "L+ /etc/windscribe/autostart - - - - ${cfg.package}/etc/windscribe/autostart"
      "d /var/run/amneziawg 0770 root windscribe -"
      "d /etc/systemd/resolved.conf.d 0755 root root -"
      "d /etc/iproute2 0755 root root -"
    ];

    systemd.services.windscribe-helper = {
      description = "Windscribe helper service";
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/opt/windscribe/helper";
        ExecStopPost = "-${cfg.package}/opt/windscribe/helper --reset-mac-addresses";
        Restart = "on-failure";
        RestartSec = 2;
        RuntimeDirectory = "windscribe";
        RuntimeDirectoryMode = "0775";
      };

      path = [
        "/run/wrappers"
      ]
      ++ (with pkgs; [
        iproute2
        systemd
        iptables
        nftables
        procps
        coreutils
        gnused
        gnugrep
        gawk
        kmod
        e2fsprogs
        util-linux
        iw
        gnupg
        ethtool
        networkmanager
        wireguard-tools
      ]);
    };
  };

  meta.maintainers = with lib.maintainers; [ aliheidary1381 ];
}
