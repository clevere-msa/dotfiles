#!/usr/bin/env bash
# Load secrets from secure stores without embedding them in dotfiles.
# This file is safe to commit because it only contains retrieval logic.

set +x

# GitHub token (uses gh auth store if available).
#if command -v gh >/dev/null 2>&1; then
#  _gh_token="$(gh auth token 2>/dev/null || true)"
#  if [ -n "$_gh_token" ]; then
#    export GH_TOKEN="$_gh_token"
#  fi
#  unset _gh_token
#fi

# Keycloak admin password (optional). Provide one of the identifiers below and
# ensure your secrets manager is already authenticated.
#
# 1Password CLI:
#   export KEYCLOAK_ADMIN_PASSWORD_OP_URI="op://<vault>/<item>/password"
if [ -n "${KEYCLOAK_ADMIN_PASSWORD_OP_URI:-}" ] && command -v op >/dev/null 2>&1; then
  _kc_pw="$(op read "$KEYCLOAK_ADMIN_PASSWORD_OP_URI" 2>/dev/null || true)"
  if [ -n "$_kc_pw" ]; then
    export KEYCLOAK_ADMIN_PASSWORD="$_kc_pw"
  fi
  unset _kc_pw
fi

# Bitwarden CLI:
#   export KEYCLOAK_ADMIN_PASSWORD_BW_ID="<item-id>"
if [ -n "${KEYCLOAK_ADMIN_PASSWORD_BW_ID:-}" ] && command -v bw >/dev/null 2>&1; then
  _kc_pw="$(bw get password "$KEYCLOAK_ADMIN_PASSWORD_BW_ID" 2>/dev/null || true)"
  if [ -n "$_kc_pw" ]; then
    export KEYCLOAK_ADMIN_PASSWORD="$_kc_pw"
  fi
  unset _kc_pw
fi

# pass (gpg):
#   export KEYCLOAK_ADMIN_PASSWORD_PASS="path/to/secret"
if [ -n "${KEYCLOAK_ADMIN_PASSWORD_PASS:-}" ] && command -v pass >/dev/null 2>&1; then
  _kc_pw="$(pass "$KEYCLOAK_ADMIN_PASSWORD_PASS" 2>/dev/null | head -n 1 || true)"
  if [ -n "$_kc_pw" ]; then
    export KEYCLOAK_ADMIN_PASSWORD="$_kc_pw"
  fi
  unset _kc_pw
fi
