#!/bin/bash
set -euo pipefail

# ⚠️ Version du Web Vault à synchroniser avec la version de Vaultwarden
# Voir : https://github.com/dani-garcia/bw_web_builds/releases
WEB_VAULT_VERSION="v2026.4.1"

# APP_HOME est défini par Clever Cloud — c'est la racine de ton app déployée
WEB_VAULT_DIR="${APP_HOME}/web-vault"

echo ">> Téléchargement du Web Vault ${WEB_VAULT_VERSION}"

mkdir -p "${WEB_VAULT_DIR}"
cd "${WEB_VAULT_DIR}"

curl -L --fail -o web-vault.tar.gz \
  "https://github.com/dani-garcia/bw_web_builds/releases/download/${WEB_VAULT_VERSION}/bw_web_${WEB_VAULT_VERSION}.tar.gz"

tar xzf web-vault.tar.gz --strip-components=1
rm web-vault.tar.gz

echo ">> Web Vault installé dans ${WEB_VAULT_DIR}"
ls "${WEB_VAULT_DIR}" | head -10

