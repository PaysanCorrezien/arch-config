#!/bin/bash
# Setup git identity configuration
# Prompts for name/email if not already set

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

# Prompt for name if not set
if [[ -z "$GIT_NAME" ]]; then
  read -p "Enter your name: " GIT_NAME
  if [[ -z "$GIT_NAME" ]]; then
    echo "Name cannot be empty."
    exit 1
  fi
fi
git config --global user.name "$GIT_NAME"

# Prompt for email if not set
if [[ -z "$GIT_EMAIL" ]]; then
  read -p "Enter your email: " GIT_EMAIL
  if [[ -z "$GIT_EMAIL" ]]; then
    echo "Email cannot be empty."
    exit 1
  fi
fi
git config --global user.email "$GIT_EMAIL"

echo ""
echo "Git identity configured:"
echo "  Name:  $GIT_NAME"
echo "  Email: $GIT_EMAIL"
echo ""
echo "Git setup complete!"
