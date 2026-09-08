<?php
ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

if (
	($_SESSION["userContext"] ?? "") !== "admin" ||
	(($_SESSION["look"] ?? "") === "admin" && ($_SESSION["POLICY_SYSTEM_PROTECTED_ADMIN"] ?? "") === "yes")
) {
	http_response_code(403);
	exit();
}

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
	header("Location: /list/domain/");
	exit();
}
verify_csrf($_POST);
$token = $_POST["cloudflare_token"] ?? "";
if (!is_string($token) || $token === "" || strlen($token) > 4096 || str_contains($token, "\n") || str_contains($token, "\r")) {
	$_SESSION["error_msg"] = _("Cloudflare token is invalid.");
	header("Location: /list/domain/");
	exit();
}

$process = proc_open(HESTIA_CMD . "v-add-dns-provider-cloudflare", [
	0 => ["pipe", "w"],
	1 => ["pipe", "r"],
	2 => ["pipe", "r"],
], $pipes);
if (!is_resource($process)) {
	$_SESSION["error_msg"] = _("Cloudflare provider could not be saved.");
} else {
	fwrite($pipes[0], $token . "\n");
	fclose($pipes[0]);
	stream_get_contents($pipes[1]);
	stream_get_contents($pipes[2]);
	fclose($pipes[1]);
	fclose($pipes[2]);
	if (proc_close($process) === 0) {
		$_SESSION["ok_msg"] = _("Cloudflare DNS provider has been saved.");
	} else {
		$_SESSION["error_msg"] = _("Cloudflare token verification failed.");
	}
}
header("Location: /list/domain/");
exit();
