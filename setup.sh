#!/usr/bin/env bash
# Installe et configure automatiquement le site vitrine TunPark (WordPress).
# Usage : ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "❌ Fichier .env manquant : cp .env.example .env  puis choisissez les mots de passe."; exit 1; }
set -a; . ./.env; set +a

SITE_URL="http://localhost:8080"
ADMIN_USER="admin"
ADMIN_PASS="${ADMIN_PASS:?définir ADMIN_PASS dans .env}"
ADMIN_EMAIL="admin@tunipark.local"
FORM_URL="https://forms.gle/M4h7abuUiKpAuG5WA"
APP_URL="$SITE_URL/application/"   # page « en cours de travaux » ; à remplacer plus tard avec ./set-app-link.sh <lien>
CONTACT_EMAIL="contact.tunpark@gmail.com"   # reçoit les messages du formulaire de contact
SENDER_EMAIL="redsys2026@gmail.com"         # compte Gmail qui envoie (configuré avec ./set-smtp.sh)

wp() { docker compose run --rm -T cli wp "$@"; }

echo "==> Démarrage des conteneurs (WordPress + MariaDB)"
docker compose up -d db wordpress phpmyadmin

echo "==> Attente de la base de données et de WordPress..."
for i in $(seq 1 60); do
  # (pas de "wp db check" : le client MariaDB exige SSL et échoue)
  if docker compose run --rm -T cli sh -c 'test -f /var/www/html/wp-config.php && php -r "mysqli_connect(\"db\",\"wp\",getenv(\"WORDPRESS_DB_PASSWORD\"),\"wordpress\");"' >/dev/null 2>&1; then break; fi
  sleep 3
  [ "$i" = 60 ] && { echo "WordPress ne répond pas. Voir : docker compose logs"; exit 1; }
done

if wp core is-installed >/dev/null 2>&1 && [ "$(wp option get tunipark_setup_done 2>/dev/null || true)" = "1" ]; then
  echo "Le site est déjà installé : $SITE_URL"
  exit 0
fi

echo "==> Installation de WordPress"
wp core install --url="$SITE_URL" --title="TunPark" \
  --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" \
  --admin_email="$ADMIN_EMAIL" --skip-email
wp language core install fr_FR --activate
wp option update blogdescription "Garez. Réservez. Simplifiez."
wp option update timezone_string "Africa/Tunis"
wp rewrite structure '/%postname%/' --hard

echo "==> Thème et plugins"
wp theme install astra --activate
wp plugin install contact-form-7 flamingo --activate
wp language plugin install contact-form-7 flamingo fr_FR || true
wp plugin delete akismet hello >/dev/null 2>&1 || true
wp theme delete twentytwentythree twentytwentyfour >/dev/null 2>&1 || true
wp post delete 1 2 3 --force >/dev/null 2>&1 || true   # contenu d'exemple

echo "==> Images"
LOGO_ID=$(wp media import /project/assets/logo.png --title="Logo TunPark" --porcelain)
ICON_ID=$(wp media import /project/assets/logo-icon.png --title="Icône TunPark" --porcelain)
PHOTO_ID=$(wp media import /project/assets/parking-photo.jpg --title="Photo parking" --porcelain)
MOCKUPS_ID=$(wp media import /project/assets/app-mockups.jpg --title="Aperçu application" --porcelain)
BANNER_ID=$(wp media import /project/assets/banniere.jpg --title="Bannière TunPark" --porcelain)
url_of() { wp eval "echo wp_get_attachment_url($1);"; }
PHOTO_URL=$(url_of "$PHOTO_ID")
MOCKUPS_URL=$(url_of "$MOCKUPS_ID")
BANNER_URL=$(url_of "$BANNER_ID")
wp theme mod set custom_logo "$LOGO_ID"
wp option update site_icon "$ICON_ID"

echo "==> Enregistrement des messages (table wp_tunipark_contacts) + SMTP"
docker compose run --rm -T cli sh -c 'mkdir -p /var/www/html/wp-content/mu-plugins && cp /project/wp/mu-plugins/*.php /var/www/html/wp-content/mu-plugins/'

echo "==> Formulaire de contact"
CF7_ID=$(wp eval '
$f = WPCF7_ContactForm::get_template(array("title" => "Contact TunPark", "locale" => "fr_FR"));
$p = $f->get_properties();
$p["form"] = file_get_contents("/project/content/contact-form.txt");
$p["mail"]["subject"] = "Nouveau message de [your-name] – TunPark";
$p["mail"]["body"] = file_get_contents("/project/content/email-notification.html");
$p["mail"]["use_html"] = true;
$p["mail"]["recipient"] = "'"$CONTACT_EMAIL"'";
$p["mail"]["sender"] = "TunPark <'"$SENDER_EMAIL"'>";
$p["mail"]["additional_headers"] = "Reply-To: [your-email]";
$f->set_properties($p);
echo $f->save();')

echo "==> Pages"
mkdir -p build
render() {
  sed -e "s|{{FORM_URL}}|$FORM_URL|g" -e "s|{{APP_URL}}|$APP_URL|g" \
      -e "s|{{PHOTO_URL}}|$PHOTO_URL|g" -e "s|{{MOCKUPS_URL}}|$MOCKUPS_URL|g" -e "s|{{BANNER_URL}}|$BANNER_URL|g" \
      -e "s|{{CF7_ID}}|$CF7_ID|g" -e "s|{{SITE_URL}}|$SITE_URL|g" "content/$1" > "build/$1"
}
render home.html
render contact.html
render application.html
HOME_ID=$(wp post create /project/build/home.html --post_type=page --post_status=publish \
  --post_title="Accueil" --post_name=accueil --porcelain)
CONTACT_ID=$(wp post create /project/build/contact.html --post_type=page --post_status=publish \
  --post_title="Contact" --post_name=contact --porcelain)

APPPAGE_ID=$(wp post create /project/build/application.html --post_type=page --post_status=publish \
  --post_title="Application" --post_name=application --porcelain)

# Pages pleine largeur, sans titre ni barre latérale (Astra)
for id in "$HOME_ID" "$CONTACT_ID" "$APPPAGE_ID"; do
  wp post meta update "$id" site-post-title disabled
  wp post meta update "$id" site-sidebar-layout no-sidebar
  wp post meta update "$id" site-content-layout page-builder
  wp post meta update "$id" ast-site-content-layout full-width-container
done

wp option update show_on_front page
wp option update page_on_front "$HOME_ID"

echo "==> Menu"
wp menu create "Principal"
wp menu item add-post principal "$HOME_ID" --title="Accueil"
wp menu item add-post principal "$CONTACT_ID" --title="Contact"
FORM_ITEM=$(wp menu item add-custom principal "Formulaire" "$FORM_URL" --target=_blank --porcelain)
wp post meta update "$FORM_ITEM" _menu_item_classes '["tp-menu-btn"]' --format=json
wp menu location assign principal primary
wp menu location assign principal mobile_menu || true

echo "==> Style (charte TunPark : #A6CE39 / #0D253D, Poppins)"
wp eval 'wp_update_custom_css_post(file_get_contents("/project/content/custom.css"));'
wp eval '
$s = get_option("astra-settings", array());
$s["display-site-title-responsive"] = array("desktop" => 0, "tablet" => 0, "mobile" => 0);
$s["display-site-tagline-responsive"] = array("desktop" => 0, "tablet" => 0, "mobile" => 0);
$s["ast-header-responsive-logo-width"] = array("desktop" => 190, "tablet" => 170, "mobile" => 140);
$s["footer-copyright-editor"] = "© [current_year] TunPark — Garez. Réservez. Simplifiez.";
update_option("astra-settings", $s);'

wp option update tunipark_app_url "$APP_URL"
wp option update tunipark_setup_done 1
wp rewrite flush --hard

cat <<EOF

✅ Site prêt !
   Site      : $SITE_URL
   Admin     : $SITE_URL/wp-admin
   Login     : $ADMIN_USER
   Password  : $ADMIN_PASS

   Messages du formulaire de contact : wp-admin → Messages clients
   Base de données (phpMyAdmin)      : http://localhost:8081  (wp / mot de passe DB_PASSWORD du .env)
   Activer l'envoi des emails        : ./set-smtp.sh  ($SENDER_EMAIL → $CONTACT_EMAIL)
   Lien de l'application (plus tard) : ./set-app-link.sh https://...
EOF
