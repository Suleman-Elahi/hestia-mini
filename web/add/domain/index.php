<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "DOMAIN";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check POST request for domain
if (!empty($_POST["ok"])) {
	// Check token
	verify_csrf($_POST);

	// Check empty fields
	if (empty($_POST["v_domain"])) {
		$errors[] = _("Domain");
	}
	if (empty($_POST["v_targets"])) {
		$errors[] = _("Backend Targets");
	}
	if (!empty($errors[0])) {
		foreach ($errors as $i => $error) {
			if ($i == 0) {
				$error_msg = $error;
			} else {
				$error_msg = $error_msg . ", " . $error;
			}
		}
		$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), $error_msg);
	}

	// Set domain name to lowercase and remove www prefix
	$v_domain = preg_replace("/^www./i", "", $_POST["v_domain"]);
	$v_domain = strtolower(trim($v_domain));
	$v_domain_arg = quoteshellarg($v_domain);

	// Get algorithm
	$v_algorithm = !empty($_POST["v_algorithm"]) ? $_POST["v_algorithm"] : "round_robin";
	$v_algorithm_arg = quoteshellarg($v_algorithm);

	// Get SSL option
	$v_ssl = !empty($_POST["v_ssl"]) ? $_POST["v_ssl"] : "no";
	$v_ssl_arg = quoteshellarg($v_ssl);

	// Process backend targets (one per line)
	$v_targets_raw = trim($_POST["v_targets"]);
	$targets = array_filter(array_map('trim', explode("\n", $v_targets_raw)));

	if (empty($targets)) {
		$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), _("Backend Targets"));
	}

	// Build targets string for CLI (space-separated)
	$v_targets_arg = quoteshellarg(implode(" ", $targets));

	// Add domain
	if (empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"v-add-domain " .
				$user .
				" " .
				$v_domain_arg .
				" " .
				$v_targets_arg .
				" " .
				$v_algorithm_arg .
				" " .
				$v_ssl_arg .
				" yes",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Flush field values on success
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = htmlify_trans(
			sprintf(
				_("Domain {%s} has been created successfully. / {Open %s}"),
				htmlentities($v_domain),
				htmlentities($v_domain),
			),
			"</a>",
			'<a href="/edit/domain/?domain=' . htmlentities($v_domain) . '&token=' . $_SESSION["token"] . '">',
		);
		unset($v_domain, $v_targets, $v_algorithm, $v_ssl);
	}
}

// Render page
if (empty($v_domain)) {
	$v_domain = "";
}
if (empty($v_targets)) {
	$v_targets = "";
}
if (empty($v_algorithm)) {
	$v_algorithm = "round_robin";
}
if (empty($v_ssl)) {
	$v_ssl = "no";
}

$accept = $_GET["accept"] ?? "";

render_page($user, $TAB, "add_domain");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
