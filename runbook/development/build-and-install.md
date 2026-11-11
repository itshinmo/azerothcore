# Build and install

## When to use

After a source change that needs compiling, after a CMake option change, or when installing a new
build.

## Prerequisites

- Dependencies from [setup-macos.md](setup-macos.md).
- An out-of-source build directory; in-source builds are blocked.

## Steps

1. Configure:

   ```bash
   cmake -S . -B build \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo \
     -DSCRIPTS=static -DMODULES=static \
     -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
   ```

   Useful options:
   - `-DBUILD_TESTING=ON` — Google Test target
   - `-DNOPCH=1` — disable precompiled headers
   - `-DTOOLS_BUILD=all` — extractors and `dbimport`
   - `-DAPPS_BUILD=auth-only|world-only|none`
   - `-DCMAKE_CXX_FLAGS=-Werror` — warnings as errors
   - `-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY` — avoids a macOS SDK try-link failure when
     `-Werror` is set; it does not change the real build
   - `-DDISABLED_AC_MODULES="mod1;mod2"`

2. Build:

   ```bash
   cmake --build build -j"$(sysctl -n hw.ncpu)"
   ```

3. Install:

   ```bash
   cmake --install build
   ```

   Layout: `env/dist/bin/{authserver,worldserver}`, `env/dist/etc/*.conf.dist`. Existing configs are
   not overwritten by default.

4. Run unit tests if configured:

   ```bash
   ctest --test-dir build -R unit --output-on-failure
   # or
   ./build/src/test/unit_tests
   ```

5. Run the linters:

   ```bash
   python apps/codestyle/codestyle-cpp.py
   python apps/codestyle/codestyle-sql.py
   ```

## Verification

- Build exits 0.
- `env/dist/bin/worldserver --version` prints the revision.
- `env/dist/bin/worldserver -d` and `authserver -d` exit 0 with the configured databases.
- Unit tests pass.

## Troubleshooting

- **CMake cannot find MySQL/OpenSSL:** pass the Homebrew prefixes.
- **Stale build:** remove `build/CMakeCache.txt` and reconfigure; do not delete local configs.
- **PCH errors:** reconfigure with `-DNOPCH=1`.
- **Linker errors after a module change:** reconfigure so the module list is regenerated.

## Notes

- The upstream docs mention `var/build/obj`; this checkout uses `build/`. Use the actual directory.
- `TOOLS_BUILD=none` is the current default; extractors and `dbimport` are not installed.
- `compile_commands.json` is exported automatically for editors.

## References

- [.agents/docs/build.md](../../.agents/docs/build.md)
- [setup-macos.md](setup-macos.md)
- [CMakeLists.txt](../../CMakeLists.txt)
- [conf/dist/config.cmake](../../conf/dist/config.cmake)
