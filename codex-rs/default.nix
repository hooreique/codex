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
    "150.4.0" = {
      aarch64-apple-darwin = {
        archive = "00adbb48798848c77550441c68673a5e8529b8e1b73eabcdee232cb39b40f4a1";
        bindings = "ca5adf0cf89c9a70ad460ae73648b2fe89b74aa113b3cb7f757b6a02b758394f";
      };
      aarch64-unknown-linux-gnu = {
        archive = "d1517eed405468537029b005d5fe997ec74d5c8d351f916b3a6df20b7d2811ba";
        bindings = "7727826ae479bdb645e807239fb12d1f8e2e23de7a6cf16f5ee592690d1d8506";
      };
      x86_64-apple-darwin = {
        archive = "e0d9bb64e8b3a034c2930c83972f3f35760211148342fa0407b38250ef330856";
        bindings = "ca5adf0cf89c9a70ad460ae73648b2fe89b74aa113b3cb7f757b6a02b758394f";
      };
      x86_64-unknown-linux-gnu = {
        archive = "a35c75d1f26e6a983885a45b33490a4ebe54f05050568b32b89cfb421b30b583";
        bindings = "7727826ae479bdb645e807239fb12d1f8e2e23de7a6cf16f5ee592690d1d8506";
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
    "mxc-sdk-1.0.0" = "sha256-jJyMp5rXXD6EAxH9p9xxwUXc+MDgdGFEchDWrjU50VU=";
    "nucleo-0.5.0" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "nucleo-matcher-0.3.1" = "sha256-Hm4SxtTSBrcWpXrtSqeO0TACbUxq3gizg1zD/6Yw/sI=";
    "rmcp-3.3.0" = "sha256-+VPObwPVKUy28cAd23RuorPAB9owaMTK0MDxuWHZdWQ=";
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
