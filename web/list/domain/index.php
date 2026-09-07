<?php
use function Hestiacp\quoteshellarg\quoteshellarg;
$TAB = "DOMAIN";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// List domains
exec(HESTIA_CMD . "v-list-domains $user json", $output, $return_var);
$data = json_decode(implode("", $output), true) ?? [];
if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}
unset($output);

render_page($user, $TAB, "list_domain");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
