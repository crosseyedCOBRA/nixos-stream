{ config, pkgs, username, inputs, ... }:

let
  wallpaper = ./assets/wallpaper.jpg;
in
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    libnotify
    playerctl
    brightnessctl
    pavucontrol
    pulseaudio # provides pactl, used by the volume keybindings below
    flameshot
    xclip
    feh

    polkit_gnome
  ];

  home.sessionVariables = {
    EDITOR = "vim";
  };

  # `xsession.enable` is deliberately left off (it would generate an
  # unconditional ~/.xsession, and the system-provided Cinnamon session
  # from services.xserver.desktopManager.cinnamon is what should be used
  # instead). Every session's generic launch script still sources
  # ~/.xprofile if present though, so recreate just that one piece by
  # hand: without it, home.sessionVariables (EDITOR, etc.) never reach
  # the session's actual process tree, only systemd-managed user services.
  home.file.".xprofile".text = ''
    . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
  '';

  # Cinnamon owns desktop/session-level theming itself (Settings > Themes,
  # backed by its own org.cinnamon.desktop.interface dconf schema) -- these
  # gtk/qt blocks just set sane defaults at the GTK/Qt toolkit level for
  # any app that reads them directly, regardless of DE.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    colorScheme = "dark";
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    style.name = "adwaita-dark";
  };

  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Sets the Cinnamon desktop background directly via dconf so the machine
  # doesn't boot to a stock Mint-Y background -- everything else about
  # theming (panel layout, accent color, etc.) is left to Cinnamon's own
  # Settings app.
  dconf.settings."org/cinnamon/desktop/background" = {
    picture-uri = "file://${wallpaper}";
    picture-options = "zoom";
  };

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings.user = {
      name = "crosseyedCOBRA";
      email = "crosseyedcobra@gmail.com";
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        opacity = 0.95;
        padding = {
          x = 10;
          y = 10;
        };
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        size = 10;
      };
    };
  };

  # Replaces the Awesome-spawned polkit agent (previously started from
  # rc.lua). Cinnamon's session is properly systemd-integrated
  # (systemd.packages includes cinnamon-session), so WantedBy on
  # graphical-session.target reliably autostarts this here, unlike the old
  # setup where Awesome's own startup script had to spawn it manually.
  systemd.user.services.polkit-agent = {
    Unit = {
      Description = "Polkit authentication agent";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.enable = true;
  xdg.configFile."fastfetch/config.jsonc".source = ./fastfetch/config.jsonc;
}
