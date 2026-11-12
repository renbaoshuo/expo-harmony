/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const Help = `Usage: expo-harmony <command> [project] [options]

Commands:
  start                 Start Expo Metro for Harmony development
  runtime               Describe project requirements; --client file checks compatibility
  runtime --publish     Embed capabilities from prepared native build inputs
  prebuild              Safely recreate the Harmony native project with Expo CNG
  prebuild --no-clean   Apply changes to the existing Harmony native project
  prebuild --check      Compare generated desired state without project writes
  build                 Build a HAP without selecting or contacting a device
  doctor                Validate config, Metro, RNOH, SDK, and signing
  modules list          List native module candidates and their discovery source
  modules inspect       Resolve Harmony metadata (--package narrows the result)
  modules verify        Validate module config, registration conflicts and safe paths
  export                Export an OTA update, assets, metadata, and source map
  export:embed          Export validated Hermes bytecode, assets, and a source map
  run                   Build, install, and launch the Harmony app

Options:
  --no-install          Skip dependency install (prebuild) or HAP install (run)
  --npm|--yarn|--pnpm|--bun
                        Select the package manager used by prebuild dependency install
  --skip-dependency-update <packages>
                        Preserve comma-separated dependency versions
  --device <id-or-name> Select an HDC target or start a local emulator by name
  --variant <mode>      Build debug or release (default: debug)
  --no-bundler          Use an already-running Expo Metro server
  --app-id <bundleName>
                        Launch another installed app (requires --no-install when different)
  --host <hostname>     Advertised LAN hostname or IPv4 address (start, run)
  --private-key-path <path>
                        Sign development manifests using the configured Updates certificate
  --port <number>       Metro and device reverse port (default: 8081)
  --sync                Recreate the CNG project before building
  --output-dir <path>   OTA export directory (default: dist)
  --asset-url <url>     HTTP(S) root hosting exported OTA assets
  --check               Validate an existing export without writing
  --reset-cache         Reset Metro while exporting or starting
  -c, --clear           Alias for --reset-cache (start)
  -h, --help            Show this help
`;
