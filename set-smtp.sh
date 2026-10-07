#!/usr/bin/env bash
# Configure l'envoi des emails du formulaire de contact via Gmail.
# Usage : ./set-smtp.sh
# Nécessite un "mot de passe d'application" Gmail : https://myaccount.google.com/apppasswords
set -euo pipefail
cd "$(dirname "$0")"

wp() { docker compose run --rm -T cli wp "$@"; }

GMAIL="${GMAIL:-}"
if [ -z "$GMAIL" ]; then
  read -r -p "Compte Gmail qui envoie les emails [redsys2026@gmail.com] : " GMAIL
  GMAIL="${GMAIL:-redsys2026@gmail.com}"
fi
GMAIL="${GMAIL// /}"
[[ "$GMAIL" == *@*.* ]] || { echo "❌ Adresse Gmail invalide."; exit 1; }
echo "Compte Gmail utilisé pour envoyer : $GMAIL"
echo "(les messages du formulaire arrivent à contact.tunpark@gmail.com)"
read -r -s -p "Mot de passe d'application Gmail (16 lettres, ne s'affiche pas) : " PASS
echo
PASS="${PASS// /}"   # Google l'affiche avec des espaces
[ ${#PASS} -eq 16 ] || { echo "❌ Le mot de passe d'application doit faire 16 caractères."; exit 1; }

wp config set TUNIPARK_SMTP_USER "$GMAIL" --type=constant >/dev/null
wp config set TUNIPARK_SMTP_PASS "$PASS" --type=constant >/dev/null

TO="contact.tunpark@gmail.com"   # boîte qui reçoit les messages du formulaire
echo "==> Envoi d'un email de test : $GMAIL → $TO ..."
if wp eval "add_action( 'wp_mail_failed', function ( \$e ) { echo 'Erreur : ', \$e->get_error_message(), PHP_EOL; } );
exit( wp_mail( '$TO', 'TunPark – test', 'La configuration email du site TunPark fonctionne.' ) ? 0 : 1 );"; then
  echo "✅ Email envoyé ! Vérifiez la boîte $TO (et le dossier Spam)."
else
  echo "❌ Échec de l'envoi. Vérifiez le mot de passe d'application puis relancez ./set-smtp.sh"
  exit 1
fi
