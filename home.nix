{ config, pkgs, username, inputs, ... }:

let
  wallpaper = ./assets/wallpaper.jpg;

  # Palette pulled from assets/wallpaper.jpg (deep space navy, nebula
  # blue/purple, warm cloud orange, coral planet surface).
  colors = {
    bg = "#0a0e1a";
    bgAlt = "#14162a";
    surface = "#1a1b26";
    border = "#292e42";
    text = "#c0caf5";
    muted = "#565f89";
    blue = "#7aa2f7";
    purple = "#9d7cd8";
    orange = "#ff9e64";
    pink = "#f7768e";
  };
in
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    inputs.quickshell.packages.${pkgs.system}.default
    libnotify
    playerctl
    brightnessctl
    pavucontrol
    pulseaudio # provides pactl, used by the volume keybindings below
    flameshot
    xclip
    feh
    thunar

    polkit_gnome
    (writeShellScriptBin "polkit-agent" ''
      exec ${polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
    '')

    # Screens otherwise never blank (DPMS/screensaver are disabled at
    # Awesome startup, see rc.lua) -- this is the one place DPMS gets
    # turned back on, for exactly as long as the session is locked, so
    # the monitors do still sleep, just only while locked. i3lock itself
    # is installed system-wide by `programs.i3lock.enable` in
    # configuration.nix (required for it to actually authenticate).
    (writeShellScriptBin "lock-screen" ''
      ${xset}/bin/xset s on
      ${xset}/bin/xset dpms 30 30 30
      ${i3lock}/bin/i3lock --nofork
      ${xset}/bin/xset s off
      ${xset}/bin/xset -dpms
    '')

    (writeShellScriptBin "power-menu" ''
      choice=$(printf 'Lock\nLogout\nSuspend\nReboot\nShutdown' | \
        ${rofi}/bin/rofi -dmenu -p "Power" -theme-str 'listview { lines: 5; }')
      case "$choice" in
        Lock) lock-screen ;;
        Logout) ${awesome}/bin/awesome-client 'awesome.quit()' ;;
        Suspend) ${systemd}/bin/systemctl suspend ;;
        Reboot) ${systemd}/bin/systemctl reboot ;;
        Shutdown) ${systemd}/bin/systemctl poweroff ;;
      esac
    '')
  ];

  home.sessionVariables = {
    EDITOR = "vim";
    GTK_THEME = "Adwaita:dark";
  };

  # `xsession.enable` is deliberately left off (it would also generate an
  # unconditional ~/.xsession that hijacks every login-screen session choice
  # back into i3 — see the multi-session setup below). But every session's
  # generic launch script still sources ~/.xprofile if present, so recreate
  # just that one piece by hand: without it, home.sessionVariables (EDITOR,
  # GTK_THEME, QT_QPA_PLATFORMTHEME, etc.) never reach the session's actual
  # process tree, only systemd-managed services like quickshell.
  home.file.".xprofile".text = ''
    . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
  '';

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

  programs.rofi = {
    enable = true;
    terminal = "${pkgs.alacritty}/bin/alacritty";
    font = "JetBrainsMono Nerd Font 11";
    theme =
      let
        inherit (config.lib.formats.rasi) mkLiteral;
      in
      {
        "*" = {
          bg = mkLiteral colors.bg;
          bg-alt = mkLiteral colors.bgAlt;
          surface = mkLiteral colors.surface;
          border-color = mkLiteral colors.border;
          fg = mkLiteral colors.text;
          fg-muted = mkLiteral colors.muted;
          accent = mkLiteral colors.blue;
          urgent = mkLiteral colors.pink;

          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@fg";

          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          spacing = mkLiteral "0px";
        };

        window = {
          background-color = mkLiteral "@bg";
          border = mkLiteral "2px";
          border-color = mkLiteral "@accent";
          border-radius = mkLiteral "10px";
          width = mkLiteral "600px";
          location = mkLiteral "center";
        };

        mainbox = {
          padding = mkLiteral "16px";
          spacing = mkLiteral "12px";
          children = map mkLiteral [ "inputbar" "listview" ];
        };

        inputbar = {
          background-color = mkLiteral "@surface";
          border-radius = mkLiteral "8px";
          padding = mkLiteral "10px 12px";
          spacing = mkLiteral "8px";
          children = map mkLiteral [ "prompt" "entry" ];
        };

        prompt = {
          text-color = mkLiteral "@accent";
        };

        entry = {
          text-color = mkLiteral "@fg";
          placeholder = "Search...";
          placeholder-color = mkLiteral "@fg-muted";
        };

        listview = {
          background-color = mkLiteral "transparent";
          lines = 8;
          spacing = mkLiteral "4px";
          scrollbar = false;
          fixed-height = false;
        };

        element = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@fg-muted";
          padding = mkLiteral "8px 10px";
          border-radius = mkLiteral "6px";
        };

        element-icon = {
          size = mkLiteral "1.2em";
          vertical-align = mkLiteral "0.5";
        };

        element-text = {
          vertical-align = mkLiteral "0.5";
          text-color = mkLiteral "inherit";
        };

        "element selected" = {
          background-color = mkLiteral "@accent";
          text-color = mkLiteral "@bg";
        };

        "element urgent" = {
          text-color = mkLiteral "@urgent";
        };

        message = {
          background-color = mkLiteral "@surface";
          border-radius = mkLiteral "8px";
          padding = mkLiteral "8px";
        };

        textbox = {
          text-color = mkLiteral "@fg";
        };
      };
  };

  services.picom = {
    enable = true;
    backend = "glx";
    vSync = true;
    # Fading was the actual cause of a perceived lag on every redraw (even
    # something as instant as fastfetch felt like it had a delay before
    # appearing) -- confirmed by testing with fade disabled while leaving
    # everything else (shadow, vsync, backend) unchanged.
    fade = false;
    shadow = true;
    # vsync-aware frame pacing deliberately delays each render to just
    # before the next vblank to cut latency, but on the desktop this
    # machine's config was copied from, it was actually reintroducing the
    # same perceived redraw lag on bursty output like fastfetch -- disabled
    # here too, leaving vsync itself (tear-free) on. Worth re-testing on
    # this machine's NVIDIA/glx combo in case the tradeoff differs.
    extraArgs = [ "--no-frame-pacing" ];
    # Tooltips/menus/dnd previews are small, short-lived popups -- a full
    # drop shadow on them (the default) looks oversized and out of place,
    # most noticeably as a heavy box around Zen's context menus and
    # tooltips. Kept out of `shadowExclude` (which would also strip
    # shadows from normal windows matching a rule) since wintypes lets us
    # target just these transient window types.
    wintypes = {
      tooltip = { shadow = false; };
      utility = { shadow = false; };
      dnd = { shadow = false; };
      popup_menu = { opacity = 1.0; shadow = false; };
      dropdown_menu = { opacity = 1.0; shadow = false; };
    };
    settings = {
      corner-radius = 6;
    };
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        follow = "mouse";
        width = 300;
        height = 300;
        origin = "top-right";
        offset = "10x50";
        frame_width = 2;
      };
      urgency_normal = {
        timeout = 6;
      };
    };
  };

  xdg.cacheFile."awesome/.keep".text = "";

  # Managed as a systemd unit so that `home-manager switch` restarts it
  # automatically whenever shell.qml or the quickshell package changes,
  # without needing to log out. Not `WantedBy = [ "graphical-session.target" ]`
  # since Awesome's own rc.lua is what starts/restarts it (see the tag-state
  # export + restart trigger there), matching the pattern of a supervised
  # service that recovers automatically if it ever dies mid-session.
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell status bar";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${inputs.quickshell.packages.${pkgs.system}.default}/bin/quickshell -p %h/.config/quickshell/shell.qml";
      Restart = "on-failure";
    };
  };

  xdg.enable = true;
  xdg.configFile."quickshell/shell.qml".source = ./quickshell/shell.qml;
  xdg.configFile."quickshell/nix-snowflake-white.svg".source = ./assets/nix-snowflake-white.svg;
  xdg.configFile."awesome/rc.lua".source = ./awesome/rc.lua;
  xdg.configFile."awesome/theme.lua".source = ./awesome/theme.lua;
  xdg.configFile."awesome/wallpaper.jpg".source = wallpaper;
  xdg.configFile."quickshell/awesome-view-tag.sh" = {
    source = ./awesome/view-tag.sh;
    executable = true;
  };
  xdg.configFile."fastfetch/config.jsonc".source = ./fastfetch/config.jsonc;
}
