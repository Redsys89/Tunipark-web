<?php
/**
 * Plugin Name: TunPark – Contacts & Email
 * Description: Enregistre chaque message du formulaire de contact dans la table wp_tunipark_contacts,
 *              affiche la liste dans l'admin et envoie les emails via Gmail SMTP.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function tunipark_contacts_table() {
	global $wpdb;
	return $wpdb->prefix . 'tunipark_contacts';
}

/* ---------- 1. Création de la table ---------- */
add_action( 'init', function () {
	if ( get_option( 'tunipark_contacts_db' ) === '1' ) {
		return;
	}
	global $wpdb;
	require_once ABSPATH . 'wp-admin/includes/upgrade.php';
	$table   = tunipark_contacts_table();
	$charset = $wpdb->get_charset_collate();
	dbDelta( "CREATE TABLE $table (
		id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		nom varchar(190) NOT NULL DEFAULT '',
		email varchar(190) NOT NULL DEFAULT '',
		telephone varchar(50) NOT NULL DEFAULT '',
		message text NOT NULL,
		email_envoye tinyint(1) NOT NULL DEFAULT 0,
		date_envoi datetime NOT NULL,
		PRIMARY KEY  (id),
		KEY email (email)
	) $charset;" );
	update_option( 'tunipark_contacts_db', '1' );
} );

function tunipark_smtp_configured() {
	return defined( 'TUNIPARK_SMTP_USER' ) && defined( 'TUNIPARK_SMTP_PASS' );
}

// Sans Gmail configuré, on n'essaie pas d'envoyer l'email : le client voit "Merci"
// et le message reste enregistré dans la base.
add_filter( 'wpcf7_skip_mail', function ( $skip ) {
	return $skip || ! tunipark_smtp_configured();
} );

/* ---------- 2. Enregistrement à chaque envoi du formulaire ---------- */
add_action( 'wpcf7_submit', function ( $form, $result ) {
	if ( ! in_array( $result['status'], array( 'mail_sent', 'mail_failed' ), true ) ) {
		return; // champs invalides ou spam : rien à enregistrer
	}
	$submission = WPCF7_Submission::get_instance();
	if ( ! $submission ) {
		return;
	}
	$data = $submission->get_posted_data();
	global $wpdb;
	$wpdb->insert( tunipark_contacts_table(), array(
		'nom'          => sanitize_text_field( $data['your-name'] ?? '' ),
		'email'        => sanitize_email( $data['your-email'] ?? '' ),
		'telephone'    => sanitize_text_field( $data['your-phone'] ?? '' ),
		'message'      => sanitize_textarea_field( $data['your-message'] ?? '' ),
		'email_envoye' => ( 'mail_sent' === $result['status'] && tunipark_smtp_configured() ) ? 1 : 0,
		'date_envoi'   => current_time( 'mysql' ),
	) );
}, 10, 2 );

/* ---------- 3. Page admin "Messages clients" ---------- */
add_action( 'admin_menu', function () {
	add_menu_page( 'Messages clients', 'Messages clients', 'manage_options',
		'tunipark-contacts', 'tunipark_contacts_page', 'dashicons-email-alt', 25 );
} );

function tunipark_contacts_page() {
	global $wpdb;
	$rows = $wpdb->get_results( 'SELECT * FROM ' . tunipark_contacts_table() . ' ORDER BY date_envoi DESC LIMIT 500' );
	echo '<div class="wrap"><h1>Messages clients (' . count( $rows ) . ')</h1>';
	echo '<table class="widefat striped"><thead><tr><th>Date</th><th>Nom</th><th>Email</th><th>Téléphone</th><th>Message</th><th>Email envoyé</th></tr></thead><tbody>';
	if ( ! $rows ) {
		echo '<tr><td colspan="6">Aucun message pour le moment.</td></tr>';
	}
	foreach ( $rows as $r ) {
		printf( '<tr><td>%s</td><td>%s</td><td><a href="mailto:%3$s">%3$s</a></td><td>%s</td><td>%s</td><td>%s</td></tr>',
			esc_html( $r->date_envoi ), esc_html( $r->nom ), esc_html( $r->email ), esc_html( $r->telephone ),
			nl2br( esc_html( $r->message ) ), $r->email_envoye ? '✅' : '❌' );
	}
	echo '</tbody></table></div>';
}

/* ---------- 4. Envoi des emails via Gmail SMTP ---------- */
// Les identifiants sont définis dans wp-config.php par ./set-smtp.sh
// L'expéditeur par défaut "wordpress@localhost" est refusé : on utilise le compte Gmail.
add_filter( 'wp_mail_from', function ( $from ) {
	return tunipark_smtp_configured() ? TUNIPARK_SMTP_USER : $from;
} );
add_filter( 'wp_mail_from_name', function () {
	return 'TunPark';
} );
add_action( 'phpmailer_init', function ( $mailer ) {
	if ( ! tunipark_smtp_configured() ) {
		return;
	}
	$mailer->isSMTP();
	$mailer->Host       = 'smtp.gmail.com';
	$mailer->Port       = 587;
	$mailer->SMTPSecure = 'tls';
	$mailer->SMTPAuth   = true;
	$mailer->Username   = TUNIPARK_SMTP_USER;
	$mailer->Password   = TUNIPARK_SMTP_PASS;
	$mailer->setFrom( TUNIPARK_SMTP_USER, 'TunPark', false );
} );
