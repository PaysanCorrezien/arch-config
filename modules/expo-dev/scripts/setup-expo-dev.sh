#!/usr/bin/env bash
# Post-install setup for the expo-dev module.
# Idempotent: safe to re-run.
#
# Performs:
#   1. chown /opt/android-sdk to the target user (AUR pkg installs as root).
#   2. Accept all Android SDK licenses.
#   3. Install platform-tools, emulator, platforms;android-35, build-tools;35.0.0,
#      and a Google Play system image for the emulator.
#   4. Create the capped Chirac API 35 tablet AVD when missing.
#   5. Install Maestro CLI to ~/.maestro (user-scoped).
#   6. Install EAS CLI globally via npm (requires npm in PATH).

set -euo pipefail

ANDROID_HOME="/opt/android-sdk"
JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
AVD_NAME="Chirac_Tablet_API_35"
DEVICE_PROFILE="pixel_tablet"
SYSTEM_IMAGE="system-images;android-35;google_apis_playstore;x86_64"
AVD_RAM_MB="4096"
AVD_CORES="2"

echo "=== Expo Dev Setup ==="

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

run_as_user() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" -H "$@"
  else
    "$@"
  fi
}

# 1. Ensure SDK dir is owned by the target user
if [ -d "$ANDROID_HOME" ]; then
  current_owner="$(stat -c '%U' "$ANDROID_HOME")"
  if [ "$current_owner" != "$target_user" ]; then
    echo "-> Chowning $ANDROID_HOME to $target_user"
    sudo chown -R "${target_user}:${target_user}" "$ANDROID_HOME"
  else
    echo "✓ $ANDROID_HOME already owned by $target_user"
  fi
else
  echo "Error: $ANDROID_HOME not found. Is android-sdk-cmdline-tools-latest installed?"
  exit 1
fi

# 2-3. Accept licenses and install SDK components
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

echo "-> Accepting SDK licenses"
# Current Android CLI releases accept licenses during component installation;
# feeding an endless `yes` stream now causes a SIGPIPE under `pipefail`.
run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
  sdkmanager --licenses </dev/null >/dev/null

# Chirac pins SDK 35 / NDK 27.0; Brassens (Expo 54, RN 0.81) builds against
# SDK 36 / NDK 27.1. Preinstall both so the first Gradle build doesn't stall.
echo "-> Installing SDK components (platform-tools, emulator, platforms 35+36, build-tools 35+36, NDK 27.0+27.1, system image)"
run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
  sdkmanager \
    "platform-tools" \
    "emulator" \
    "platforms;android-35" \
    "platforms;android-36" \
    "build-tools;35.0.0" \
    "build-tools;36.0.0" \
    "ndk;27.0.12077973" \
    "ndk;27.1.12297006" \
    "$SYSTEM_IMAGE" >/dev/null
echo "✓ SDK components installed"

# 4. Create the AVDs the project scripts expect, when missing:
#    Chirac's scripts/mobile-android-start-avds.sh defaults to the NewArch phone
#    + tablet pair; Brassens UAT targets a single x86_64 phone emulator.
for spec in "${AVD_NAME}:${DEVICE_PROFILE}" "Chirac_NewArch_API_35:pixel_7" "Brassens_Phone_API_35:pixel_7"; do
  avd="${spec%%:*}"
  device="${spec##*:}"
  if run_as_user env ANDROID_HOME="$ANDROID_HOME" PATH="$PATH" \
       avdmanager list avd 2>/dev/null | grep -q "Name: ${avd}"; then
    echo "✓ AVD ${avd} already exists"
  else
    echo "-> Creating AVD ${avd} (${device}, ${AVD_RAM_MB} MiB, ${AVD_CORES} cores)"
    echo "no" | run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
      avdmanager create avd -n "$avd" -k "$SYSTEM_IMAGE" -d "$device" --force >/dev/null
    echo "✓ AVD created"
  fi

  # Keep each UAT lane bounded even while the Windows VM is active. The
  # emulator can grow graphics caches beyond its initial allocation, but these
  # AVD values cap the guest RAM/heap and avoid consuming every host core.
  avd_config="${user_home}/.android/avd/${avd}.avd/config.ini"
  if [ -f "$avd_config" ]; then
    config_tmp="${avd_config}.tmp.$$"
    run_as_user awk -v ram="$AVD_RAM_MB" -v cores="$AVD_CORES" '
      BEGIN { ram_seen = heap_seen = cores_seen = gpu_seen = 0 }
      /^hw\.ramSize=/ { print "hw.ramSize=" ram; ram_seen = 1; next }
      /^vm\.heapSize=/ { print "vm.heapSize=512"; heap_seen = 1; next }
      /^hw\.cpu\.ncore=/ { print "hw.cpu.ncore=" cores; cores_seen = 1; next }
      /^hw\.gpu\.enabled=/ { print "hw.gpu.enabled=yes"; gpu_seen = 1; next }
      { print }
      END {
        if (!ram_seen) print "hw.ramSize=" ram
        if (!heap_seen) print "vm.heapSize=512"
        if (!cores_seen) print "hw.cpu.ncore=" cores
        if (!gpu_seen) print "hw.gpu.enabled=yes"
      }
    ' "$avd_config" > "$config_tmp"
    run_as_user mv "$config_tmp" "$avd_config"
    echo "✓ Capped ${avd} at ${AVD_RAM_MB} MiB / ${AVD_CORES} cores"
  fi
done

# 5. Maestro
if [ -x "${user_home}/.maestro/bin/maestro" ]; then
  echo "✓ Maestro already installed at ~/.maestro"
else
  echo "-> Installing Maestro CLI to ~/.maestro"
  run_as_user bash -c 'curl -fsSL "https://get.maestro.mobile.dev" | bash' >/dev/null
  echo "✓ Maestro installed"
fi

# 6. EAS CLI (global npm)
if command -v npm >/dev/null 2>&1; then
  if command -v eas >/dev/null 2>&1; then
    echo "✓ EAS CLI already installed ($(eas --version 2>&1 | head -1))"
  else
    echo "-> Installing EAS CLI globally"
    sudo npm install -g eas-cli >/dev/null
    echo "✓ EAS CLI installed"
  fi
else
  echo "⚠  npm not found — skipping EAS CLI. Enable the nodejs module to get it."
fi

# Sanity check: KVM accessible (emulator needs it)
if [ -w /dev/kvm ] && [ -r /dev/kvm ]; then
  echo "✓ /dev/kvm accessible (hardware acceleration available)"
else
  echo "⚠  /dev/kvm not accessible to $target_user — emulator will be very slow."
fi

echo
echo "=== Expo Dev Setup Complete ==="
echo "Launch emulator: emulator -avd ${AVD_NAME}"
echo "Create app:     npx create-expo-app my-app && cd my-app && npx expo run:android"
