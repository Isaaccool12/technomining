#!/usr/bin/env bash
# Скачать PDF для конвертера.
#   fetch_pdf.sh <источник> <куда>
# Источник:
#   SEN02158-15.pdf                 — файл из релиза pdf-library этого репозитория
#   https://disk.yandex.ru/...      — публичная ссылка Яндекс Диска
#   https://drive.google.com/...    — ссылка Google Диска («доступ по ссылке»)
#   https://...                     — прямая ссылка на файл
set -euo pipefail
src="$1"; dst="$2"
mkdir -p "$(dirname "$dst")"
case "$src" in
  https://disk.yandex.*|https://yadi.sk/*)
    href=$(curl -fsSL "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$src")" \
           | python3 -c 'import sys,json;print(json.load(sys.stdin)["href"])')
    curl -fL --retry 3 -o "$dst" "$href" ;;
  https://drive.google.com/*|https://docs.google.com/*)
    gdown --fuzzy -O "$dst" "$src" ;;
  http://*|https://*)
    curl -fL --retry 3 -o "$dst" "$src" ;;
  *)
    gh release download pdf-library --repo "${GITHUB_REPOSITORY:-Isaaccool12/technomining}" --pattern "$src" --output "$dst" ;;
esac
head -c 5 "$dst" | grep -q '%PDF' || { echo "::error::Скачанный файл «$src» — не PDF (проверьте ссылку или имя файла в релизе pdf-library)"; exit 1; }
echo "PDF: $src → $dst ($(du -h "$dst" | cut -f1))"
