<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
$TAB = "DOMAIN";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Check domain argument
if (empty($_GET["domain"])) {
	header("Location: /list/domain/");
	exit();
}

// Edit as someone else?
if ($_SESSION["userContext"] === "admin" && !empty($_GET["user"])) {
	$user = quoteshellarg($_GET["user"]);
	$user_plain = htmlentities($_GET["user"]);
}

$v_domain = $_GET["domain"];

// List domain
exec(
	HESTIA_CMD . "v-list-domain " . $user . " " . quoteshellarg($v_domain) . " json",
	$output,
	$return_var,
);
$data = json_decode(implode("", $output), true);
check_return_code_redirect($return_var, $output, "/list/domain/");
unset($output);

// Parse domain data
$v_algorithm = $data[$v_domain]["ALGORITHM"] ?? "round_robin";
$v_targets = $data[$v_domain]["TARGETS"] ?? "";
$v_backends = str_replace(" ", "\n", $v_targets);
$v_ssl = $data[$v_domain]["SSL"] ?? "no";
$v_suspended = $data[$v_domain]["SUSPENDED"] ?? "no";
$v_date = $data[$v_domain]["DATE"] ?? "";
$v_time = $data[$v_domain]["TIME"] ?? "";

if ($v_suspended == "yes") {
	$v_status = "suspended";
} else {
	$v_status = "active";
}

// Check POST request for domain
if (!empty($_POST["save"]) && !empty($_GET["domain"])) {
	// Check token
	verify_csrf($_POST);

	// Get algorithm
	$new_algorithm = !empty($_POST["v_algorithm"]) ? $_POST["v_algorithm"] : "round_robin";

	// Get SSL option
	$new_ssl = !empty($_POST["v_ssl"]) ? $_POST["v_ssl"] : "no";

	// Process backend targets (one per line)
	$new_targets_raw = trim($_POST["v_targets"]);
	$targets = array_filter(array_map('trim', explode("\n", $new_targets_raw)));

	if (empty($targets)) {
		$_SESSION["error_msg"] = sprintf(_('Field "%s" can not be blank.'), _("Backend Targets"));
	}

	// Build targets string for CLI (space-separated)
	$new_targets_arg = quoteshellarg(implode(" ", $targets));

	// Update domain proxy settings
	if (empty($_SESSION["error_msg"])) {
		exec(
			HESTIA_CMD .
				"v-change-domain-proxy " .
				$user .
				" " .
				quoteshellarg($v_domain) .
				" " .
				$new_targets_arg .
				" " .
				quoteshellarg($new_algorithm) .
				" " .
				quoteshellarg($new_ssl) .
				" yes",
			$output,
			$return_var,
		);
		check_return_code($return_var, $output);
		unset($output);
	}

	// Set success message
	if (empty($_SESSION["error_msg"])) {
		$_SESSION["ok_msg"] = _("Changes have been saved.");
	}
	// Redirect to prevent form resubmission
	http_response_code(303);
	header("Location: " . $_SERVER["REQUEST_URI"]);
	die();
}

// Render page
render_page($user, $TAB, "edit_domain");

// Flush session messages
unset($_SESSION["error_msg"]);
unset($_SESSION["ok_msg"]);
