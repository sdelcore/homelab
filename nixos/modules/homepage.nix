# Homepage dashboard configuration module
#
# Manages Homepage configuration files declaratively in NixOS.
# Files are written to /etc and symlinked to /opt/stacks/tools/config/homepage/
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.homepage;
in
{
  options.homepage = {
    enable = mkEnableOption "Homepage dashboard configuration";
  };

  config = mkIf cfg.enable {
    # ============================================================
    # Homepage Config Files
    # ============================================================

    # settings.yaml
    environment.etc."stacks/tools/config/homepage/settings.yaml".text = ''
      title: Homelab Dashboard

      background:
        image: https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80
        blur: sm
        saturate: 100
        brightness: 50
        opacity: 50

      theme: dark
      color: slate

      headerStyle: clean

      layout:
        Media:
          style: row
          columns: 4
        Downloads:
          style: row
          columns: 2
        Tools:
          style: row
          columns: 3
    '';

    # docker.yaml - Docker socket connections for auto-discovery
    environment.etc."stacks/tools/config/homepage/docker.yaml".text = ''
      # Docker socket connections for Homepage auto-discovery
      # Local tools VM
      tools:
        socket: /var/run/docker.sock

      # Remote arr VM - requires Docker TCP to be enabled on arr
      arr:
        host: 10.0.0.20
        port: 2375
    '';

    # widgets.yaml
    environment.etc."stacks/tools/config/homepage/widgets.yaml".text = ''
      - resources:
          cpu: true
          memory: true
          disk: /

      - search:
          provider: duckduckgo
          target: _blank
    '';

    # services.yaml (empty - auto-discovered from Docker labels)
    environment.etc."stacks/tools/config/homepage/services.yaml".text = ''
      # Services are auto-discovered from Docker labels
      # Add manual entries here if needed
    '';

    # bookmarks.yaml (empty)
    environment.etc."stacks/tools/config/homepage/bookmarks.yaml".text = ''
      # Bookmarks - add manual links here if needed
    '';

    # ============================================================
    # Symlink config to stack directory
    # ============================================================
    # Homepage expects config files in /app/config which is mounted
    # from /opt/stacks/tools/config/homepage. We symlink from /etc
    # so the files are managed by NixOS.
    systemd.tmpfiles.rules = [
      "d /opt/stacks/tools/config/homepage 0755 root root -"
      "L+ /opt/stacks/tools/config/homepage/settings.yaml - - - - /etc/stacks/tools/config/homepage/settings.yaml"
      "L+ /opt/stacks/tools/config/homepage/docker.yaml - - - - /etc/stacks/tools/config/homepage/docker.yaml"
      "L+ /opt/stacks/tools/config/homepage/widgets.yaml - - - - /etc/stacks/tools/config/homepage/widgets.yaml"
      "L+ /opt/stacks/tools/config/homepage/services.yaml - - - - /etc/stacks/tools/config/homepage/services.yaml"
      "L+ /opt/stacks/tools/config/homepage/bookmarks.yaml - - - - /etc/stacks/tools/config/homepage/bookmarks.yaml"
    ];
  };
}
