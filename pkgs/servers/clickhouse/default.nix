{
  lib,
  llvmPackages,
  llvmPackages_16,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  ninja,
  python3,
  perl,
  nasm,
  yasm,
  nixosTests,
  darwin,
  findutils,
  libiconv,

  rustSupport ? true,

  rustc,
  cargo,
  rustPlatform,
}:

let
  inherit (llvmPackages) stdenv;
  mkDerivation =
    (if stdenv.hostPlatform.isDarwin then llvmPackages_16.stdenv else llvmPackages.stdenv).mkDerivation;
in
mkDerivation rec {
  pname = "clickhouse";
  version = "24.3.7.30";

  src = fetchFromGitHub rec {
    owner = "ClickHouse";
    repo = "ClickHouse";
    rev = "v${version}-lts";
    fetchSubmodules = true;
    name = "clickhouse-${rev}.tar.gz";
    hash = "sha256-xIqn1cRbuD3NpUC2c7ZzvC8EAmg+XOXCkp+g/HTdIc0=";
    postFetch = ''
      # delete files that make the source too big
      rm -rf $out/contrib/llvm-project/llvm/test
      rm -rf $out/contrib/llvm-project/clang/test
      rm -rf $out/contrib/croaring/benchmarks

      # fix case insensitivity on macos https://github.com/NixOS/nixpkgs/issues/39308
      rm -rf $out/contrib/sysroot/linux-*
      rm -rf $out/contrib/liburing/man

      # compress to not exceed the 2GB output limit
      # try to make a deterministic tarball
      tar -I 'gzip -n' \
        --sort=name \
        --mtime=1970-01-01 \
        --owner=0 --group=0 \
        --numeric-owner --mode=go=rX,u+rw,a-s \
        --transform='s@^@source/@S' \
        -cf temp  -C "$out" .
      rm -r "$out"
      mv temp "$out"
    '';
  };

  patches = [
    # They updated the Cargo.toml without updating the Cargo.lock :/
    (fetchpatch {
      url = "https://github.com/ClickHouse/ClickHouse/commit/bccd33932b5fe17ced2dc2f27813da0b1c034afa.patch";
      revert = true;
      hash = "sha256-4idwr+G8WGuT/VILKtDIJIvbCvi6pZokJFze4dP6ExE=";
    })
    (fetchpatch {
      url = "https://github.com/ClickHouse/ClickHouse/commit/b6bd5ecb199ef8a10e3008a4ea3d96087db8a8c1.patch";
      revert = true;
      hash = "sha256-nbb/GV2qWEZ+BEfT6/9//yZf4VWdhOdJCI3PLeh6o0M=";
    })
  ];

  strictDeps = true;
  nativeBuildInputs =
    [
      cmake
      ninja
      python3
      perl
      llvmPackages.lld
    ]
    ++ lib.optionals stdenv.hostPlatform.isx86_64 [
      nasm
      yasm
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      llvmPackages.bintools
      findutils
      darwin.bootstrap_cmds
    ]
    ++ lib.optionals rustSupport [
      rustc
      cargo
      rustPlatform.cargoSetupHook
    ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  # their vendored version is too old and missing this patch: https://github.com/corrosion-rs/corrosion/pull/205
  corrosionSrc =
    if rustSupport then
      fetchFromGitHub {
        owner = "corrosion-rs";
        repo = "corrosion";
        rev = "v0.3.5";
        hash = "sha256-r/jrck4RiQynH1+Hx4GyIHpw/Kkr8dHe1+vTHg+fdRs=";
      }
    else
      null;
  corrosionDeps =
    if rustSupport then
      rustPlatform.fetchCargoVendor {
        src = corrosionSrc;
        name = "corrosion-deps";
        preBuild = "cd generator";
        hash = "sha256-ok1QLobiGBccmbEEWQxHz3ivvuT6FrOgG6wLK4gIbgU=";
      }
    else
      null;
  rustDeps =
    if rustSupport then
      rustPlatform.fetchCargoVendor {
        inherit src;
        name = "rust-deps";
        preBuild = "cd rust";
        hash = "sha256-nX5wBM8rVMbaf/IrPsqkdT2KQklQbBIGomeWSTjclR4=";
      }
    else
      null;

  dontCargoSetupPostUnpack = true;
  postUnpack = lib.optionalString rustSupport ''
    pushd source

    rm -rf contrib/corrosion
    cp -r --no-preserve=mode $corrosionSrc contrib/corrosion

    pushd contrib/corrosion/generator
    cargoDeps="$corrosionDeps" cargoSetupPostUnpackHook
    corrosionDepsCopy="$cargoDepsCopy"
    popd

    pushd rust
    cargoDeps="$rustDeps" cargoSetupPostUnpackHook
    rustDepsCopy="$cargoDepsCopy"
    cat .cargo/config.toml >> .cargo/config.toml.in
    cat .cargo/config.toml >> skim/.cargo/config.toml.in
    rm .cargo/config.toml
    popd

    popd
  '';

  postPatch =
    ''
      patchShebangs src/

      substituteInPlace src/Storages/System/StorageSystemLicenses.sh \
        --replace 'git rev-parse --show-toplevel' '$src'
      substituteInPlace utils/check-style/check-duplicate-includes.sh \
        --replace 'git rev-parse --show-toplevel' '$src'
      substituteInPlace utils/check-style/check-ungrouped-includes.sh \
        --replace 'git rev-parse --show-toplevel' '$src'
      substituteInPlace utils/list-licenses/list-licenses.sh \
        --replace 'git rev-parse --show-toplevel' '$src'
      substituteInPlace utils/check-style/check-style \
        --replace 'git rev-parse --show-toplevel' '$src'
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      sed -i 's|gfind|find|' cmake/tools.cmake
      sed -i 's|ggrep|grep|' cmake/tools.cmake
    ''
    + lib.optionalString rustSupport ''

      pushd contrib/corrosion/generator
      cargoDepsCopy="$corrosionDepsCopy" cargoSetupPostPatchHook
      popd

      pushd rust
      cargoDepsCopy="$rustDepsCopy" cargoSetupPostPatchHook
      popd

      cargoSetupPostPatchHook() { true; }
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Make sure Darwin invokes lld.ld64 not lld.
      substituteInPlace cmake/tools.cmake \
        --replace '--ld-path=''${LLD_PATH}' '-fuse-ld=lld'
    '';

  cmakeFlags =
    [
      "-DENABLE_TESTS=OFF"
      "-DCOMPILER_CACHE=disabled"
      "-DENABLE_EMBEDDED_COMPILER=ON"
    ]
    ++ lib.optional (
      stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64
    ) "-DNO_ARMV81_OR_HIGHER=1";

  env = {
    NIX_CFLAGS_COMPILE =
      # undefined reference to '__sync_val_compare_and_swap_16'
      lib.optionalString stdenv.hostPlatform.isx86_64 " -mcx16"
      +
        # Silence ``-Wimplicit-const-int-float-conversion` error in MemoryTracker.cpp and
        # ``-Wno-unneeded-internal-declaration` TreeOptimizer.cpp.
        lib.optionalString stdenv.hostPlatform.isDarwin
          " -Wno-implicit-const-int-float-conversion -Wno-unneeded-internal-declaration";
  };

  # https://github.com/ClickHouse/ClickHouse/issues/49988
  hardeningDisable = [ "fortify" ];

  postInstall = ''
    rm -rf $out/share/clickhouse-test

    sed -i -e '\!<log>/var/log/clickhouse-server/clickhouse-server\.log</log>!d' \
      $out/etc/clickhouse-server/config.xml
    substituteInPlace $out/etc/clickhouse-server/config.xml \
      --replace "<errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>" "<console>1</console>"
    substituteInPlace $out/etc/clickhouse-server/config.xml \
      --replace "<level>trace</level>" "<level>warning</level>"
  '';

  # Builds in 7+h with 2 cores, and ~20m with a big-parallel builder.
  requiredSystemFeatures = [ "big-parallel" ];

  passthru.tests.clickhouse = nixosTests.clickhouse;

  meta = with lib; {
    homepage = "https://clickhouse.com";
    description = "Column-oriented database management system";
    license = licenses.asl20;
    maintainers = with maintainers; [
      orivej
      mbalatsko
    ];

    # not supposed to work on 32-bit https://github.com/ClickHouse/ClickHouse/pull/23959#issuecomment-835343685
    platforms = lib.filter (x: (lib.systems.elaborate x).is64bit) (platforms.linux ++ platforms.darwin);
    broken = stdenv.buildPlatform != stdenv.hostPlatform;
  };
}
