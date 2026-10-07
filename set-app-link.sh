#!/usr/bin/env bash
# Met à jour le lien du bouton "Découvrir l'application" sur toutes les pages.
# Usage : ./set-app-link.sh https://lien-de-l-application
set -euo pipefail
cd "$(dirname "$0")"

NEW_URL="${1:?Usage : ./set-app-link.sh https://lien-application}"
wp() { docker compose run --rm -T cli wp "$@"; }

OLD_URL=$(wp option get tunipark_app_url)
wp search-replace "href=\"$OLD_URL\"" "href=\"$NEW_URL\"" wp_posts --include-columns=post_content
wp option update tunipark_app_url "$NEW_URL"
echo "✅ Lien de l'application mis à jour : $NEW_URL"
