{
  description = "Mike's stream PC NixOS configuration - Cinnamon + home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # Third-party overlay swapping xorg-server for the XLibre fork.
    # dev-26.11 tracks nixos-unstable (matches our nixpkgs input above).
    # NOTE: this box has an NVIDIA GPU, unlike the desktop this config was
    # copied from (AMD) -- XLibre + the proprietary NVIDIA driver is a less
    # exercised combination, so watch for X server issues after first boot.
    xlibre-overlay = {
      url = "git+https://codeberg.org/takagemacoed/xlibre-overlay?ref=dev-26.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      username = "mike";
      hostname = "nixosStream";
    in
    {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit username inputs; };
        modules = [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          ./configuration.nix
          inputs.nix-flatpak.nixosModules.nix-flatpak
          inputs.xlibre-overlay.nixosModules.overlay-xlibre-xserver
          inputs.xlibre-overlay.nixosModules.overlay-all-xlibre-drivers
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit username inputs; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    };
}
