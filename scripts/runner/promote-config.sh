#!/usr/bin/env bash
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.
# Runs inside the on-demand ACI ops runner in snet-lw-ops using the user-assigned identity
# id-<base>-lw-ops (deploy-spec section 7, D-C3, DN-M6). Downloads staged artifacts from the
# media account's staging container, verifies SHA-256, uploads under .tmp names to the live
# lwconfig file share, and renames client.net.xml before <configName>.ini for atomic promotion.

set -euo pipefail

: "${OPS_IDENTITY_ID:?OPS_IDENTITY_ID is required}"
: "${MEDIA_ACCOUNT_NAME:?MEDIA_ACCOUNT_NAME is required}"
: "${CONFIG_ACCOUNT_NAME:?CONFIG_ACCOUNT_NAME is required}"
: "${CONFIG_NAME:?CONFIG_NAME is required}"
: "${TIMESTAMP:?TIMESTAMP is required}"
: "${TARGET_FOLDER:?TARGET_FOLDER is required}"
: "${EXPECTED_INI_SHA256:?EXPECTED_INI_SHA256 is required}"

WORKDIR="/tmp/lw-promote-${TIMESTAMP}"
mkdir -p "${WORKDIR}"

az login --identity --username "${OPS_IDENTITY_ID}" --output none

for file in "client.net.xml" "${CONFIG_NAME}.ini" "${CONFIG_NAME}.json"; do
  az storage blob download \
    --account-name "${MEDIA_ACCOUNT_NAME}" \
    --container-name "staging" \
    --name "${CONFIG_NAME}/${TIMESTAMP}/${file}" \
    --file "${WORKDIR}/${file}" \
    --auth-mode login \
    --output none
done

ACTUAL_INI_SHA256="$(sha256sum "${WORKDIR}/${CONFIG_NAME}.ini" | awk '{print tolower($1)}')"
EXPECTED_LOWER="$(echo "${EXPECTED_INI_SHA256}" | tr '[:upper:]' '[:lower:]')"
if [[ "${ACTUAL_INI_SHA256}" != "${EXPECTED_LOWER}" ]]; then
  echo "LW-RESULT status=failed timestamp=${TIMESTAMP} iniSha256=${ACTUAL_INI_SHA256} detail=INI SHA-256 mismatch against expected ${EXPECTED_LOWER}"
  exit 1
fi

az storage directory create \
  --account-name "${CONFIG_ACCOUNT_NAME}" \
  --share-name "lwconfig" \
  --name "${TARGET_FOLDER}" \
  --auth-mode login \
  --output none

for file in "client.net.xml" "${CONFIG_NAME}.ini"; do
  az storage file upload \
    --account-name "${CONFIG_ACCOUNT_NAME}" \
    --share-name "lwconfig" \
    --source "${WORKDIR}/${file}" \
    --path "${TARGET_FOLDER}/${file}.tmp" \
    --auth-mode login \
    --output none
done

# Rename XML before INI so any logon during promotion reads a consistent pair (DN-M6).
for file in "client.net.xml" "${CONFIG_NAME}.ini"; do
  az storage file copy start \
    --account-name "${CONFIG_ACCOUNT_NAME}" \
    --destination-share "lwconfig" \
    --destination-path "${TARGET_FOLDER}/${file}" \
    --source-account-name "${CONFIG_ACCOUNT_NAME}" \
    --source-share "lwconfig" \
    --source-path "${TARGET_FOLDER}/${file}.tmp" \
    --auth-mode login \
    --output none
  az storage file delete \
    --account-name "${CONFIG_ACCOUNT_NAME}" \
    --share-name "lwconfig" \
    --path "${TARGET_FOLDER}/${file}.tmp" \
    --auth-mode login \
    --output none
done

echo "LW-RESULT status=promoted timestamp=${TIMESTAMP} target=${TARGET_FOLDER} iniSha256=${ACTUAL_INI_SHA256} detail=Promoted client.net.xml then ${CONFIG_NAME}.ini to lwconfig/${TARGET_FOLDER}"
