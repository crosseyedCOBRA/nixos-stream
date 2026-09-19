{ config, pkgs, lib, username, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- Bootloader ---
  # Assumes UEFI. If this machine is legacy BIOS, swap this for boot.loader.grub instead.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Deliberately NOT linuxPackages_latest here, unlike the desktop config:
  # this box runs the proprietary NVIDIA driver, whose out-of-tree kernel
  # module can lag a newly-bumped kernel by days/weeks and break boot after
  # an update. The default `linuxPackages` is better-exercised with NVIDIA
  # and this machine needs to not break mid-stream.
  boot.kernelPackages = pkgs.linuxPackages;

  # --- Networking ---
  networking.hostName = "nixosStream"; # keep in sync with flake.nix's `hostname` let-binding
  networking.networkmanager.enable = true;

  # --- Locale / time ---
  time.timeZone = "America/New_York"; # change to your timezone
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
  services.xserver.xkb.layout = "us";

  # --- Nix / nixpkgs ---
  nixpkgs.config.allowUnfree = true; # non-free software allowed
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # --- Graphics (NVIDIA) ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit libs
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    # This machine's GPU is a GTX 1080 (Pascal). NVIDIA's open kernel
    # modules only support Turing (RTX 20xx) and newer, so `open = false`
    # (the proprietary module) is required here, not just the safe default.
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # --- Audio (pipewire) ---
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # --- X11 + Awesome ---
  # Awesome is the only WM/DE on this system: chosen over i3, dwm, the
  # Wayland compositors tried earlier, and the XFCE/Cinnamon DEs tried
  # for testing, for its native dwindle/master layouts, real mouse-driven
  # tiling, and per-monitor tags without needing patches.
  services.xserver.enable = true;
  services.xserver.windowManager.awesome.enable = true;
  # Reverted from greetd+tuigreet back to lightdm: greetd's X11 handling
  # (sessions run through tuigreet's `startx` wrapper) turned out to be
  # broken too (sessions opened and crashed within the same second per the
  # journal), and since the Wayland WMs greetd was for are gone, there's no
  # remaining reason not to go back to the known-good lightdm setup.
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.defaultSession = "none+awesome";

  # Required for i3lock to actually authenticate: this generates
  # /etc/pam.d/i3lock. Without it, i3lock has no PAM stack to check the
  # password against and rejects every attempt, correct or not -- the
  # i3 window manager module sets this automatically, but nothing does
  # for Awesome, so it must be requested explicitly here.
  programs.i3lock.enable = true;

  # --- Monitor layout ---
  # This box's monitor layout isn't known yet -- the desktop config's
  # hardcoded 3-monitor xrandr setupCommands was deliberately dropped, along
  # with the matching awesome/rc.lua block and the HDMI-mirror filtering in
  # quickshell/shell.qml. Once you know this machine's actual output names
  # (`xrandr --query` after first boot), add a setupCommands block back here
  # if the default auto-layout isn't what you want.

  # --- Theming ---
  # Required by home-manager's `dconf.settings` (used for GTK dark mode).
  programs.dconf.enable = true;

  # --- nix-ld ---
  # Patches the dynamic loader for non-Nix binaries, e.g. compiled wheels
  # (MarkupSafe, etc.) pulled in by pip inside a python venv, which
  # otherwise can't find their libs since NixOS has no /lib64/ld-linux.
  programs.nix-ld.enable = true;

  # --- Flatpak + desktop portals ---
  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # --- Fonts ---
  # Trimmed to what's actually referenced (alacritty/rofi use JetBrainsMono
  # Nerd Font) instead of the desktop config's full several-GB nerd-fonts set.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    font-awesome
    nerd-fonts.jetbrains-mono
  ];

  # --- zram swap ---
  zramSwap.enable = true;

  # --- User account ---
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.bash;
  };
  # No password is set here. After the first rebuild, log in at the TTY
  # and run `passwd` to set one (or `passwd mike` as root).

  environment.systemPackages = with pkgs; [
    vim
    fastfetch
    wget
    curl
    git
    unzip
    p7zip
    file
    python3
    claude-code
    vesktop
    xdg-user-dirs
    inputs.zen-browser.packages.${pkgs.system}.default # beta channel

    # --- Streaming ---
    # Native OBS build, not the Flatpak: nixpkgs' obs-studio ships Browser
    # Source out of the box (`browserSupport` defaults to true, bundling
    # CEF), both Aitum plugins we need are packaged too, and NVENC is a
    # core plugin (obs-nvenc) built unconditionally on Linux x64 -- its
    # only build dependency, nv-codec-headers-12, is already an
    # unconditional buildInput of nixpkgs' obs-studio derivation. At
    # runtime it dlopens libnvidia-encode.so via /run/opengl-driver,
    # which the `hardware.nvidia` block above populates. So nothing is missing
    # versus the Flatpak. Wrapped together via wrapOBS so the plugins
    # actually get picked up (OBS_PLUGINS_PATH).
    (wrapOBS {
      plugins = with obs-studio-plugins; [
        obs-aitum-multistream # multi-platform simulcasting
        obs-vertical-canvas # Aitum Vertical
      ];
    })

    # --- Video editing ---
    # Free (non-Studio) DaVinci Resolve. nixpkgs builds it in a buildFHSEnv
    # wrapper and fetches the official .run installer itself during build
    # (replicates Blackmagic's download-registration flow) -- no manual
    # download needed. GPU accel rides on the system OpenCL ICD, which
    # `hardware.nvidia`/`hardware.graphics` above already provide. Note:
    # the free edition has no H.264/H.265 hardware encode/decode and no
    # advanced noise reduction -- kdenlive is kept installed alongside as
    # a fallback in case Resolve doesn't work out on this machine. kdenlive
    # itself already bundles ffmpeg-full + mlt + frei0r (see its nixpkgs
    # derivation), so it needs no extra codec packages. Resolve free is the
    # one with real codec gaps (no H.264/H.265 encode, limited decode, no
    # ffmpeg of its own) -- the standalone `ffmpeg` below is the standard
    # workaround, transcoding problem footage to something Resolve free can
    # ingest natively (e.g. DNxHR/ProRes). Its default build already covers
    # x264/x265/VP8/VP9/AV1(decode)/Opus/AAC/MP3, plus NVENC/NVDEC since
    # this box has an NVIDIA GPU (verified in nixpkgs' ffmpeg derivation).
    davinci-resolve
    kdePackages.kdenlive
    ffmpeg
  ];

  # Companion setting for hardware.nvidia.videoAcceleration (defaults to
  # true, which already wires nvidia-vaapi-driver into
  # hardware.graphics.extraPackages) -- makes VA-API clients (kdenlive/MLT,
  # mpv, browsers, etc.) reliably pick the NVIDIA VA-API backend for
  # hardware-accelerated decode instead of guessing.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "nvidia";

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken. Do NOT bump this on later
  # upgrades — it should stay at whatever it was on first install.
  system.stateVersion = "26.05";
}
