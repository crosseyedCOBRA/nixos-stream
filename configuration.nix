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
    # `stable` (the production branch) has moved past Pascal -- confirmed
    # on the actual hardware, the 595.99.02 installer refused to probe the
    # GPU and pointed at the 580.xx legacy branch instead. legacy_580 is
    # nixpkgs' LTSB build (580.178.04, supported through Aug 2028) and is
    # the correct branch for this GPU going forward.
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
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

  # --- X11 + Cinnamon ---
  # Switched from a hand-rolled Awesome + quickshell + rofi + picom + dunst
  # setup to a full, stock desktop environment: less to hand-maintain on a
  # machine that just needs to reliably run OBS/Resolve/Kdenlive, not be a
  # tiling-WM daily driver. Cinnamon's NixOS module (services.xserver.
  # desktopManager.cinnamon) pulls in its own compositor (Muffin), panel,
  # screen lock (cinnamon-screensaver, with its own PAM service already
  # wired up by the module), polkit integration, portals, and a full app
  # suite (Nemo file manager, GNOME Terminal, calculator, text editor,
  # archive manager, screenshot tool, etc. via services.cinnamon.apps.enable,
  # on by default) -- see `environment.cinnamon.excludePackages` if any of
  # that default app set isn't wanted later.
  #
  # This also means the desktop-specific hardcoded 3-monitor xrandr setup
  # and HDMI-mirror handling from the old Awesome/quickshell config doesn't
  # carry over (it's gone along with those files) -- configure monitors via
  # Cinnamon's own Settings > Display panel after first login instead.
  services.xserver.enable = true;
  services.xserver.desktopManager.cinnamon.enable = true;
  # Reverted from greetd+tuigreet back to lightdm: greetd's X11 handling
  # (sessions run through tuigreet's `startx` wrapper) turned out to be
  # broken too (sessions opened and crashed within the same second per the
  # journal), and since the Wayland WMs greetd was for are gone, there's no
  # remaining reason not to go back to the known-good lightdm setup. The
  # Cinnamon module defaults lightdm's greeter to Mint's "slick" greeter
  # automatically once it's enabled below.
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.defaultSession = "cinnamon"; # X11 session; see pkgs.cinnamon.passthru.providedSessions

  # --- nix-ld ---
  # Patches the dynamic loader for non-Nix binaries, e.g. compiled wheels
  # (MarkupSafe, etc.) pulled in by pip inside a python venv, which
  # otherwise can't find their libs since NixOS has no /lib64/ld-linux.
  programs.nix-ld.enable = true;

  # --- Flatpak ---
  # No manual xdg.portal block needed here: the Cinnamon module above
  # already enables xdg-desktop-portal with the xapp + gtk portal backends
  # and its own config package.
  services.flatpak.enable = true;

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
    #
    # davinci-resolve commented out for now: its fixed-output derivation
    # (nixpkgs scripts Blackmagic's own download API live at build time
    # rather than fetching a pinned tarball URL) hit a SHA256 hash
    # mismatch building on the actual stream PC hardware. Re-enable once
    # that's root-caused/retested -- if it's a one-time drift the pinned
    # `outputHash` in nixpkgs' davinci-resolve package.nix just needs
    # overriding to the actual hash from the error; if it's flaky/
    # unreliable, drop it for good and lean on kdenlive below instead.
    # davinci-resolve
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
