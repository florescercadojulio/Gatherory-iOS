#!/usr/bin/env bash
# Verifies that every SwiftUI literal is represented in the String Catalog and
# that each supported locale has a reviewed translation. Run this in CI after
# changing user-facing copy.
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$repo_root/Gatherory/Localizable.xcstrings"
scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/gatherory-localization.XXXXXX")"
trap 'rm -rf "$scratch_directory"' EXIT

source_catalog="$scratch_directory/Localizable.xcstrings"
cp "$catalog" "$source_catalog"

swift_sources=()
while IFS= read -r swift_source; do
  swift_sources+=("$swift_source")
done < <(find "$repo_root/Gatherory" -name '*.swift' -print)
xcrun xcstringstool extract \
  --SwiftUI \
  --modern-localizable-strings \
  --output-format xcstrings \
  --append \
  --output-directory "$scratch_directory" \
  "${swift_sources[@]}"

node --input-type=module - "$catalog" "$source_catalog" <<'NODE'
import fs from "node:fs"

const [catalogPath, extractedPath] = process.argv.slice(2)
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"))
const extracted = JSON.parse(fs.readFileSync(extractedPath, "utf8"))
const sourceKeys = Object.keys(catalog.strings)
const extractedKeys = Object.keys(extracted.strings)
const missingExtractedKeys = extractedKeys.filter((key) => !sourceKeys.includes(key))
const missingTranslations = sourceKeys.flatMap((key) => {
  const unit = catalog.strings[key].localizations?.es?.stringUnit
  return unit?.state === "translated" && typeof unit.value === "string"
    ? []
    : [`es: ${JSON.stringify(key)}`]
})

if (missingExtractedKeys.length || missingTranslations.length) {
  if (missingExtractedKeys.length) {
    console.error("New SwiftUI copy is missing from Localizable.xcstrings:")
    missingExtractedKeys.forEach((key) => console.error(`  ${JSON.stringify(key)}`))
  }
  if (missingTranslations.length) {
    console.error("Catalog entries need a reviewed translation:")
    missingTranslations.forEach((entry) => console.error(`  ${entry}`))
  }
  process.exit(1)
}

// Catalog keys remain stable even when product terminology changes. Check the
// strings people actually receive, including English source-language fallbacks.
const legacyEventTerm = /\bworkspaces?\b|\bespacios? de (?:trabajo|planificaci[oó]n)\b/i
const outdatedCopy = sourceKeys.flatMap((key) => ["en", "es"].flatMap((locale) => {
  const value = catalog.strings[key].localizations?.[locale]?.stringUnit?.value ?? key
  return legacyEventTerm.test(value) ? [`${locale}: ${JSON.stringify(key)} => ${value}`] : []
}))
if (outdatedCopy.length) {
  console.error("Consumer copy must use event terminology:")
  outdatedCopy.forEach((entry) => console.error(`  ${entry}`))
  process.exit(1)
}

console.log(`Localization coverage verified for ${sourceKeys.length} strings in English and Spanish.`)
NODE
