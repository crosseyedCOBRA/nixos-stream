{
  description = "Mike's stream PC NixOS configuration - Cinnamon + home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned separately from the main `nixpkgs` input above, for
    # davinci-resolve only. That package's fetch is a fixed-output
    # derivation that scripts Blackmagic's download API live at build time
    # and pins the resulting file's hash -- Blackmagic periodically
    # re-hosts a new installer under an *existing* version string (hit on
    # this machine 2026-10-22: "21.1"'s pinned hash no longer matched what
    # Blackmagic actually serves for "21.1"). Nixpkgs' own fix is just a
    # new commit bumping the version/hash once that happens; this input
    # tracks the commit where that landed (21.1 -> 21.1.1) instead of
    # hand-patching the hash here. If Blackmagic drifts again, bump *this*
    # input to whatever commit nixpkgs next fixes it in -- not the main
    # nixpkgs pin above.
    nixpkgs-davinci-resolve.url = "github:NixOS/nixpkgs/134e02770b7d23bcb1a7dcd763580e5d75a8b4e9";

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
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit username inputs; };
            home-manager.users.${username} = import ./home.nix;
            # Without this, activation hard-fails instead of switching
            # whenever a home.nix-managed path (e.g. ~/.gtkrc-2.0, written
            # by Cinnamon itself before home-manager ever touched it) already
            # exists on disk -- back it up with this suffix instead.
            home-manager.backupFileExtension = "hm-bak";
          }
        ];
      };
    };
}
