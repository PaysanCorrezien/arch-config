#!/bin/bash
# Setup git identity configuration
# This script guides the user through manual git configuration

set -e

echo "=== Git Identity Setup ==="
echo ""

# Check if git identity is already configured
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  echo "Git identity already configured:"
  echo "  Name:  $GIT_NAME"
  echo "  Email: $GIT_EMAIL"
  echo ""
  read -p "Keep this configuration? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo "Git identity unchanged."
    exit 0
  fi
fi

# Manual action required
echo ""
echo "=========================================="
echo "  MANUAL ACTION REQUIRED"
echo "=========================================="
echo ""
echo "Please configure your git identity by running:"
echo ""
echo "  git config --global user.name \"Your Name\""
echo "  git config --global user.email \"your@email.com\""
echo ""
echo "=========================================="
echo ""

while true; do
  read -p "Have you completed the git configuration? [y/n] " -n 1 -r
  echo
  case $REPLY in
    [Yy])
      # Verify configuration was set
      GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
      GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

      if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
        echo ""
        echo "Warning: Git identity still not configured."
        echo "  Name:  ${GIT_NAME:-<not set>}"
        echo "  Email: ${GIT_EMAIL:-<not set>}"
        echo ""
        read -p "Continue anyway? [y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          break
        fi
      else
        echo ""
        echo "Git identity configured:"
        echo "  Name:  $GIT_NAME"
        echo "  Email: $GIT_EMAIL"
        break
      fi
      ;;
    [Nn])
      echo "Please complete the configuration and run this script again."
      exit 1
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

echo ""
echo "Git setup complete!"
