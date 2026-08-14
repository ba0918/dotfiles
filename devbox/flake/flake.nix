{
  description = "PHP with timecop extension for devbox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        php = pkgs.php85;
        timecop = php.buildPecl {
          pname = "timecop";
          version = "1.8.0";
          src = pkgs.fetchFromGitHub {
            owner = "kiddivouchers";
            repo = "php-timecop";
            rev = "v1.8.0";
            sha256 = "sha256-4xawkEFwFC+043jFRYNGYVoKbv4HV2UpOvao1ngbEK0=";
          };
        };
      in
      {
        packages.default = php.withExtensions ({ enabled, all }: enabled ++ (with all; [ xdebug pcov ]) ++ [ timecop ]);
      });
}
