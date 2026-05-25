#!/usr/bin/env bash
# Post-install setup for the expo-dev module.
# Idempotent: safe to re-run.
#
# Performs:
#   1. chown /opt/android-sdk to the target user (AUR pkg installs as root).
#   2. Accept all Android SDK licenses.
#   3. Install platform-tools, emulator, platforms;android-35, build-tools;35.0.0,
#      and a Google Play system image for the emulator.
#   4. Create a Pixel API 35 AVD if none exists.
#   5. Install Maestro CLI to ~/.maestro (user-scoped).
#   6. Install EAS CLI globally via npm (requires npm in PATH).

set -euo pipefail

ANDROID_HOME="/opt/android-sdk"
JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
AVD_NAME="Pixel_API_35"
SYSTEM_IMAGE="system-images;android-35;google_apis_playstore;x86_64"

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
yes | run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
  sdkmanager --licenses >/dev/null

echo "-> Installing SDK components (platform-tools, emulator, platform 35, build-tools 35, system image)"
run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
  sdkmanager \
    "platform-tools" \
    "emulator" \
    "platforms;android-35" \
    "build-tools;35.0.0" \
    "$SYSTEM_IMAGE" >/dev/null
echo "✓ SDK components installed"

# 4. Create default AVD if missing
if run_as_user env ANDROID_HOME="$ANDROID_HOME" PATH="$PATH" \
     avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}"; then
  echo "✓ AVD ${AVD_NAME} already exists"
else
  echo "-> Creating AVD ${AVD_NAME}"
  echo "no" | run_as_user env ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME" PATH="$PATH" \
    avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d "pixel_7" --force >/dev/null
  echo "✓ AVD created"
fi

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
