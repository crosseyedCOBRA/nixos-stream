{ config, pkgs, username, inputs, ... }:

let
  wallpaper = ./assets/wallpaper.jpg;

  # Shared between programs.bash and programs.fish below so bash (kept
  # around for compat/scripts) and fish (the actual login shell) don't
  # drift out of sync with each other.
  shellAliases = {
    # Applies configuration.nix/home.nix changes without touching flake
    # inputs (flake.lock) -- this is the one to run after editing either
    # file, day to day.
    rebuild = "sudo nixos-rebuild switch --flake /home/mike/nixos-stream#nixosStream";
    # Updates every flake input (nixpkgs, home-manager, nix-flatpak,
    # xlibre-overlay, zen-browser) to its latest commit and rewrites
    # flake.lock -- does NOT apply anything by itself, just bumps
    # versions; follow with `rebuild` to actually rebuild against them.
    # Leaves nixpkgs-davinci-resolve alone since that input is pinned to
    # a single exact commit (see flake.nix), not a branch, so there's
    # nothing for `flake update` to move there anyway.
    update = "nix flake update --flake /home/mike/nixos-stream";
    # The common case: update inputs, rebuild against them, and update
    # Flatpaks too (services.flatpak.enable's own packages aren't
    # touched by either flake update or nixos-rebuild -- Flatpak manages
    # that store independently). Spelled out in full (not
    # "update && rebuild") so it doesn't depend on the shell having
    # already expanded those other two aliases in this session.
    upgrade = "nix flake update --flake /home/mike/nixos-stream && sudo nixos-rebuild switch --flake /home/mike/nixos-stream#nixosStream && flatpak update -y";
  };
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
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
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

  # Cinnamon reads its own icon theme from this key (Nemo, panel, menu,
  # applets) rather than the gtk.iconTheme settings.ini above -- same
  # reason the wallpaper needs the dconf override above instead of being
  # left to Cinnamon's own default (Mint-Y here, since it ships with
  # services.cinnamon.apps.enable's default app set).
  dconf.settings."org/cinnamon/desktop/interface".icon-theme = "Papirus-Dark";

  programs.home-manager.enable = true;

  # Kept enabled even though fish (below) is the actual login shell now --
  # covers `bash -i`/scripts that explicitly want bash with these aliases
  # too, and costs nothing to leave on.
  programs.bash = {
    enable = true;
    inherit shellAliases;
  };

  # The actual login shell (configuration.nix sets `shell = pkgs.fish;` on
  # the user account; programs.fish.enable there just registers it in
  # /etc/shells -- this is what actually configures it).
  programs.fish = {
    enable = true;
    inherit shellAliases;
  };

  programs.starship.enable = true;

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
