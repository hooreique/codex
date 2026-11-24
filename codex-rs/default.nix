{
  cmake,
  fetchurl,
  fetchgit,
  llvmPackages,
  openssl,
  libcap ? null,
  rustPlatform,
  pkg-config,
  lib,
  stdenv,
  buildCommit ? "dev",
  version ? "0.0.0",
  ...
}:
let
  v8Version = (lib.findFirst (pkg: pkg.name == "v8")
    (throw "v8 is missing from Cargo.lock")
    (builtins.fromTOML (builtins.readFile ./Cargo.lock)).package).version;
  v8Target = stdenv.hostPlatform.rust.rustcTarget;
  # Archive and bindings are a matching pair from the Codex V8 release.
  v8Hashes = {
    "152.2.0" = {
      aarch64-apple-darwin = {
        archive = "feab9ae0384bebaa99c1d000654462c9d42123d587185c7876aaeef7d76ff749";
        bindings = "b9d5652ebca515eb2bf4c2ee4a6551b2567117b5aa720f430d2032616dd7e3b5";
      };
      aarch64-unknown-linux-gnu = {
        archive = "1054464a623006cdf5e25ae20877002bf3edb9a2c2f3e64f44a8714742b15e87";
        bindings = "3e4d5fecdbe0f98a6017e69d7ca82519a77fb032c5eb5e4cdbecdd3e2ec519d5";
      };
      x86_64-apple-darwin = {
        archive = "bfe19d9b633b61d99780ece89690427fef4b985c6b4196536eaf94571166fc24";
        bindings = "b9d5652ebca515eb2bf4c2ee4a6551b2567117b5aa720f430d2032616dd7e3b5";
      };
      x86_64-unknown-linux-gnu = {
        archive = "b3b490f2aa809eda7f6ac727f851fb00ce8355be72827577cfaac28c7137dbcd";
        bindings = "3e4d5fecdbe0f98a6017e69d7ca82519a77fb032c5eb5e4cdbecdd3e2ec519d5";
      };
    };
  }.${v8Version}.${v8Target};
  v8Release = "https://github.com/openai/codex/releases/download/rusty-v8-v${v8Version}";
  # V8 links the pinned prebuilt archive below; its Chromium source submodules
  # are unnecessary. Fetch only the Rust crate tree when vendoring this source.
  buildRustPackage = rustPlatform.buildRustPackage.override {
    importCargoLock = rustPlatform.importCargoLock.override {
      fetchgit = args: fetchgit (args // lib.optionalAttrs
        (args.url == "https://github.com/openai-oss-forks/rusty_v8.git")
        { fetchSubmodules = false; });
    };
  };
in
buildRustPackage (_: {
  env = {
    STABLE_GIT_COMMIT = buildCommit;
    PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
      [ openssl ] ++ lib.optionals stdenv.isLinux [ libcap ]
    );
    RUSTY_V8_ARCHIVE = fetchurl {
      url = "${v8Release}/librusty_v8_ptrcomp_sandbox_release_${v8Target}.a.gz";
      sha256 = v8Hashes.archive;
    };
    RUSTY_V8_SRC_BINDING_PATH = fetchurl {
      url = "${v8Release}/src_binding_ptrcomp_sandbox_release_${v8Target}.rs";
      sha256 = v8Hashes.bindings;
    };
  } // lib.optionalAttrs (builtins.elem stdenv.hostPlatform.system [ "aarch64-linux" "x86_64-linux" ]) {
    # Reduce peak memory when building the CLI on Linux CI runners.
    CARGO_PROFILE_RELEASE_LTO = "off";
  };
  pname = "codex-rs";
  inherit version;
  cargoLock.lockFile = ./Cargo.lock;
  # Package the CLI, JavaScript host, and upstream's standalone executor.
  cargoBuildFlags = [ "-p" "codex-cli" "-p" "codex-code-mode-host" "-p" "codex-exec-server-cli" ];
  doCheck = false;
  src = ./.;

  # Patch the workspace Cargo.toml so that cargo embeds the correct version in
  # CARGO_PKG_VERSION (which the binary reads via env!("CARGO_PKG_VERSION")).
  # On release commits the Cargo.toml already contains the real version and
  # this sed is a no-op.
  postPatch = ''
    sed -i 's/^version = "0\.0\.0"$/version = "${version}"/' Cargo.toml

    # MXC's Windows-only binding check reads the first windows version from the
    # parent lockfile after Nix flattens Git workspaces into the vendor directory.
    # Codex also locks windows 0.58, although MXC correctly depends on 0.62.
    # Apply the target/feature guard to the writable vendor copy, preserving the
    # version check whenever those generated bindings are actually compiled.
    patch -d "$cargoDepsCopy/mxc-sdk-1.1.0" -p1 --fuzz=0 < ${./nix/mxc-bindings-target-check.patch}
  '';
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/codex" --version)" = "codex-cli ${version}"
    runHook postInstallCheck
  '';
  nativeBuildInputs = [
    cmake
    llvmPackages.clang
    llvmPackages.libclang.lib
    openssl
    pkg-config
  ] ++ lib.optionals stdenv.isLinux [
    libcap
  ];

  cargoLock.outputHashes = {
    "v8-152.2.0" = "sha256-BB4a6uIcuZFmbkbXzdKOPq2vTu6pfZivPkHliOHnG3c=";
    "crossterm-0.29.0" = "sha256-ETTZx1d2rQqIOk6O822k2I2Hs9+uskbLB1pLke32P1k=";
    "h3-0.0.8" = "sha256-fgE0AMj5d4iattTC/yQwnACV8uEu+KR7wD29xfEm8M0=";
    "mxc-sdk-1.1.0" = "sha256-74e6KZTaErXycDIB5LxQduNvLhv1ULHlHmjmEW7sNmk=";
    "nucleo-0.5.0" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "nucleo-matcher-0.3.1" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "rmcp-3.6.0" = "sha256-yuWdAHp7ow5RkhQfnjot3Zxy17iGnkGdGYRB3T0kUgQ=";
    "runfiles-0.1.0" = "sha256-uJpVLcQh8wWZA3GPv9D8Nt43EOirajfDJ7eq/FB+tek=";
    # Hash the Git checkout: SQLx's attributes normalize CRLF test fixtures.
    "sqlx-core-0.9.0" = "sha256-kLvUfUy6vmL9LYU7nzHv+iB6cIJm2CjDf9Yo6wpWrWg=";
    "tokio-tungstenite-0.28.0" = "sha256-fTNFTRNKyV6gwpoYzqKfBG1VKbF5Foh3OLwj9gkf44M=";
    "tungstenite-0.27.0" = "sha256-iskbqB2ebP+4iyRE4Ve5TgGXt9z12/Dpznhmwh0wrvI=";
  };

  meta = with lib; {
    description = "OpenAI Codex command‑line interface rust implementation";
    license = licenses.asl20;
    homepage = "https://github.com/openai/codex";
    mainProgram = "codex";
  };
})
