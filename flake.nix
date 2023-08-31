{
  description = "TODO";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        });
    in
    {

      # A Nixpkgs overlay.
      overlays.default = final: prev: {
        promterm-zig = with final;

          # https://nixos.org/manual/nixpkgs/unstable/#zighook
          stdenv.mkDerivation {
            pname = "promterm-zig";
            version = "0.0.1";

            src = ./.;

            nativeBuildInputs = [ zig_0_11.hook ];

            meta = {
              description = "TODO";
              changelog = "TODO";
              homepage = "TODO";
              license = lib.licenses.mit;
              maintainers = with lib.maintainers; [ pinpox ];
              platforms = lib.platforms.unix;
            };
          };
      };

      # Package
      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system}) promterm-zig;
        default = self.packages.${system}.promterm-zig;
      });
    };
}
