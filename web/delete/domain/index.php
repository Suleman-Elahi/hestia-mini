<?php
use function Hestiacp\quoteshellarg\quoteshellarg;

ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// Delete as someone else?
if ($_SESSION["userContext"] === "admin" && !empty($_GET["user"])) {
	$user = quoteshellarg($_GET["user"]);
}

// Check token
verify_csrf($_GET);

// Delete domain
if (!empty($_GET["domain"])) {
	$v_domain = quoteshellarg($_GET["domain"]);
	exec(HESTIA_CMD . "v-delete-domain " . $user . " " . $v_domain, $output, $return_var);
	check_return_code($return_var, $output);
	unset($output);
	$back = $_SESSION["back"];
	if ($return_var > 0) {
		header("Location: /list/domain/");
		exit();
	}
	if (!empty($back)) {
		header("Location: " . $back);
		exit();
	}
	header("Location: /list/domain/");
	exit();
}

$back = $_SESSION["back"];
if (!empty($back)) {
	header("Location: " . $back);
	exit();
}

header("Location: /list/domain/");
exit();
