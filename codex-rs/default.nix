{
  cmake,
  fetchurl,
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
in
rustPlatform.buildRustPackage (_: {
  env.STABLE_GIT_COMMIT = buildCommit;
  env.PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
    [ openssl ] ++ lib.optionals stdenv.isLinux [ libcap ]
  );
  env.RUSTY_V8_ARCHIVE = fetchurl {
    url = "${v8Release}/librusty_v8_ptrcomp_sandbox_release_${v8Target}.a.gz";
    sha256 = v8Hashes.archive;
  };
  env.RUSTY_V8_SRC_BINDING_PATH = fetchurl {
    url = "${v8Release}/src_binding_ptrcomp_sandbox_release_${v8Target}.rs";
    sha256 = v8Hashes.bindings;
  };
  pname = "codex-rs";
  inherit version;
  cargoLock.lockFile = ./Cargo.lock;
  # Package the CLI and its companion JavaScript host.
  cargoBuildFlags = [ "-p" "codex-cli" "-p" "codex-code-mode-host" ];
  doCheck = false;
  src = ./.;

  # Patch the workspace Cargo.toml so that cargo embeds the correct version in
  # CARGO_PKG_VERSION (which the binary reads via env!("CARGO_PKG_VERSION")).
  # On release commits the Cargo.toml already contains the real version and
  # this sed is a no-op.
  postPatch = ''
    sed -i 's/^version = "0\.0\.0"$/version = "${version}"/' Cargo.toml
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
    "crossterm-0.29.0" = "sha256-7ZzFZ6c6uU27ZxCGOPK82Aia4CzTnJwksAfbpTMPikY=";
    "h3-0.0.8" = "sha256-fgE0AMj5d4iattTC/yQwnACV8uEu+KR7wD29xfEm8M0=";
    "mxc-sdk-1.0.0" = "sha256-AI4l2yCbB/4UWweLFhEefEPqSt/ZB1V+Mk/svdAT8No=";
    "nucleo-0.5.0" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "nucleo-matcher-0.3.1" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "rmcp-3.5.1" = "sha256-yczrrD6SnXhblos5oU6fbyDc7vkRah9DsF41hcaKzi4=";
    "runfiles-0.1.0" = "sha256-uJpVLcQh8wWZA3GPv9D8Nt43EOirajfDJ7eq/FB+tek=";
    "tokio-tungstenite-0.28.0" = "sha256-V1xmnrfRWOcZZogelZEA4vvyMj2awCfHVA5/glQ6KAI=";
    "tungstenite-0.27.0" = "sha256-VVHhk7l9J/sEmG3q/UuV/sQ3f+fGsmq5vumSy8vbMvw=";
  };

  meta = with lib; {
    description = "OpenAI Codex command‑line interface rust implementation";
    license = licenses.asl20;
    homepage = "https://github.com/openai/codex";
    mainProgram = "codex";
  };
})
