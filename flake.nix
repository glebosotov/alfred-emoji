{
  description = "Offline multilingual emoji search for Alfred";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      devShells = each (pkgs: { default = pkgs.mkShell {
        packages = with pkgs; [ curl unzip zip ];
      }; });
      packages = each (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "alfred-emoji";
          version = "0.2.1";
          src = self;
          nativeBuildInputs = [ pkgs.swift pkgs.zip ];
          MACOSX_DEPLOYMENT_TARGET = "13.0";
          doCheck = true;
          checkPhase = ''
            swiftc -O Sources/Core.swift Tests/main.swift -o test-runner
            ./test-runner
          '';
          buildPhase = ''
            export HOME="$TMPDIR"
            swiftc -O -target ${pkgs.stdenv.hostPlatform.darwinArch}-apple-macosx13.0 Sources/Core.swift Sources/main.swift -o emoji
            swiftc Tools/Package.swift -o package-tool
            mkdir -p dist/Emoji.alfredworkflow.contents
            cp emoji dist/Emoji.alfredworkflow.contents/
            cp -R data dist/Emoji.alfredworkflow.contents/
            ./package-tool dist/Emoji.alfredworkflow.contents
            EMOJI_DATA="$PWD/data" alfred_workflow_cache="$TMPDIR/icons" ./emoji render-icon 👀 > dist/Emoji.alfredworkflow.contents/icon.png
            cd dist/Emoji.alfredworkflow.contents
            zip -q -r ../Emoji.alfredworkflow .
            cd ../..
          '';
          installPhase = ''
            mkdir -p "$out"
            cp dist/Emoji.alfredworkflow "$out/"
          '';
        };
      });
    };
}
