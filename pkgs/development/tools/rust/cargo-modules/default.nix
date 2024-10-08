{ lib, rustPlatform, fetchFromGitHub, stdenv, darwin }:

rustPlatform.buildRustPackage rec {
  pname = "cargo-modules";
  version = "0.16.8";

  src = fetchFromGitHub {
    owner = "regexident";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-F1hVKktU9zhdxXWhpLgymehJQlOX6WbXL2cqQGB+Y5k=";
  };

  cargoHash = "sha256-j3AYWKq7SrlNlsY7A80iwcWKW8wi6hx0U9UwDIQkXZs=";

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.apple_sdk.frameworks.CoreServices
  ];

  checkFlags = [
    "--skip=cfg_test::smoke"
    "--skip=colors::ansi::smoke"
    "--skip=colors::plain::smoke"
    "--skip=colors::truecolor::smoke"
    "--skip=focus_on::glob_path::smoke"
    "--skip=focus_on::self_path::smoke"
    "--skip=focus_on::simple_path::smoke"
    "--skip=focus_on::use_tree::smoke"
    "--skip=functions::function_body"
    "--skip=functions::function_inputs"
    "--skip=functions::function_outputs"
    "--skip=max_depth::depth_2::smoke"
    "--skip=selection::no_fns::smoke"
    "--skip=selection::no_modules::smoke"
    "--skip=selection::no_traits::smoke"
    "--skip=selection::no_types::smoke"
    "--skip=fields::enum_fields"
    "--skip=fields::struct_fields"
    "--skip=fields::tuple_fields"
    "--skip=fields::union_fields"
  ];

  meta = with lib; {
    description = "Cargo plugin for showing a tree-like overview of a crate's modules";
    mainProgram = "cargo-modules";
    homepage = "https://github.com/regexident/cargo-modules";
    changelog = "https://github.com/regexident/cargo-modules/blob/${version}/CHANGELOG.md";
    license = with licenses; [ mpl20 ];
    maintainers = with maintainers; [ figsoda rvarago matthiasbeyer ];
  };
}
