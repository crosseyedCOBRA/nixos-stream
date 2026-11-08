{ config, pkgs, lib, username, inputs, ... }:

let
  # See flake.nix's `nixpkgs-davinci-resolve` input comment: davinci-resolve
  # is pulled from a separately-pinned nixpkgs commit instead of the main
  # `nixpkgs` input, to dodge a Blackmagic-side hash drift on the package's
  # fixed-output source fetch. Needs its own allowUnfree since it's a
  # fully separate pkgs instantiation from the main `pkgs` argument above.
  davinciPkgs = import inputs.nixpkgs-davinci-resolve {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
in
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
  # Fully disabled, not just port-opened -- every listening service on
  # this machine is unfiltered from the network as a result. Deliberate
  # choice made 2026-10-23; revisit if this box's exposure changes.
  networking.firewall.enable = false;

  # --- Locale / time ---
  time.timeZone = "America/New_York"; # change to your timezone
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
  services.xserver.xkb.layout = "us";

  # --- Nix / nixpkgs ---
  nixpkgs.config.allowUnfree = true; # non-free software allowed
  nixpkgs.overlays = [
    # nixpkgs' obs-studio postFixup adds /run/opengl-driver to the RUNPATH
    # of obs-nvenc.so itself (via addDriverRunpath), but misses the
    # separate obs-nvenc-test helper binary that obs-nvenc.so spawns as a
    # subprocess to *probe* NVENC support before OBS will show the
    # encoder in its UI at all. Without this, that helper can't dlopen
    # libnvidia-encode.so.1 ("Cannot load libnvidia-encode.so.1" in OBS's
    # log, confirmed by running `obs-nvenc-test` directly on this
    # machine), the probe reports nvenc_supported=false, and NVENC never
    # appears as an encoder option even though the actual NVENC plugin
    # and driver are both fine -- confirmed working once this binary's
    # RUNPATH includes /run/opengl-driver/lib by hand. Still true as of
    # current nixos-unstable, so patch it here rather than wait on
    # upstream.
    (final: prev: {
      obs-studio = prev.obs-studio.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          addDriverRunpath $out/bin/.obs-nvenc-test-wrapped
        '';
      });
    })
  ];
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
  # Stock X.Org. A third-party overlay swapping this for the XLibre fork
  # was tried and dropped 2026-11-08: its xlibre-xserver derivation reused
  # nixpkgs' own xorg-server patch set applied against XLibre's unrelated
  # source tree, so any routine nixpkgs update that touched those patches
  # (not even an XLibre version change) could break the build -- hit this
  # exactly once and confirmed there's no way to isolate it from the main
  # `nixpkgs` input (NixOS's xserver module has no `package`-style option;
  # the overlay works by replacing the global `xorg-server` attribute in
  # place, so there's no override point short of pinning the *whole*
  # system's nixpkgs, which defeats being able to update normally).
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

  # --- Shell ---
  # Needs to be enabled as a system program (not just installed via
  # home.packages/home-manager) so it's registered in /etc/shells --
  # otherwise `shell = pkgs.fish;` below and chsh both refuse it.
  programs.fish.enable = true;

  # --- User account ---
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.fish;
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
    #
    # NVENC not showing up in OBS's encoder list despite all of the above
    # was a separate nixpkgs packaging gap in the obs-nvenc-test helper
    # binary's RUNPATH -- see the obs-studio overlay up in the Nix/nixpkgs
    # section for the actual fix/explanation.
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
    # Root-caused the earlier SHA256 hash mismatch: it was a one-time
    # drift, not a flaky/broken fetch. Blackmagic re-hosted a new
    # installer file under the already-released "21.1" version string, so
    # nixpkgs' pinned hash for that fetch (current as of this config's
    # main `nixpkgs` pin) no longer matched. Confirmed by reproducing the
    # live fetch+hash by hand and finding nixpkgs had already fixed it
    # upstream (version bump to 21.1.1, new hash) in a commit newer than
    # this config's main nixpkgs pin -- pulled from there via the
    # `davinciPkgs` instance above instead of waiting on/forcing a full
    # nixpkgs bump for the whole system.
    davinciPkgs.davinci-resolve
    ffmpeg

    # kdePackages.kdenlive (nixpkgs build) was the original fallback here,
    # but dropped 2026-10-31 after it crashed mid-edit: coredump showed a
    # genuine heap-corruption abort inside FFmpeg's threaded H.264 decoder
    # (frame_worker_thread -> h264_decode_frame -> ff_thread_get_ext_buffer
    # -> malloc_printerr), triggered via MLT's libmltavformat.so, which
    # nixpkgs' `mlt` derivation pins to its own ffmpeg (8.1.3) independent
    # of kdenlive's own direct ffmpeg-full link (9.0.2) -- not a config or
    # project-file issue, a decoder bug in that specific ffmpeg build.
    # Switched to the Flatpak build instead (installed imperatively, see
    # the Flatpak section below) on the chance its bundled ffmpeg doesn't
    # hit the same path; not a confirmed fix, just the next thing to try.

    # --- Social Stream Ninja ---
    # Merges Twitch/YouTube/Kick chat into one feed: an OBS browser-source
    # overlay here, and a combined chat dock viewable from any browser
    # (the gaming PC, over the same session). Ships as either a Chrome
    # extension or a standalone Electron desktop app -- the extension is
    # out since this config's browser is Zen (Firefox-based), so it's the
    # desktop app's Linux AppImage instead. Upstream only publishes
    # AppImages (no nixpkgs package, no stable per-version download URL to
    # pin a fetchurl hash against -- releases are frequent), so it's run
    # via appimage-run against a manually-downloaded file rather than
    # packaged as a proper Nix derivation.
    appimage-run
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
