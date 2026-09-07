<?php
use function Hestiacp\quoteshellarg\quoteshellarg;
$TAB = "DOMAIN";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

// List reverse-proxy domains and mail domains in one Domains view.
exec(HESTIA_CMD . "v-list-domains $user json", $output, $return_var);
$data = json_decode(implode("", $output), true) ?? [];
unset($output);

foreach ($data as &$domain) {
	$domain["TYPE"] = "proxy";
}
unset($domain);

exec(HESTIA_CMD . "v-list-mail-domains $user json", $output, $return_var);
$mail_domains = json_decode(implode("", $output), true) ?? [];
unset($output);

foreach ($mail_domains as $domain_name => $mail_domain) {
	if (isset($data[$domain_name])) {
		$data[$domain_name]["TYPE"] = "proxy_mail";
		continue;
	}

	$data[$domain_name] = [
		"TYPE" => "mail",
		"SSL" => $mail_domain["SSL"] ?? "no",
		"SUSPENDED" => $mail_domain["SUSPENDED"] ?? "no",
		"TIME" => $mail_domain["TIME"] ?? "",
		"DATE" => $mail_domain["DATE"] ?? "",
	];
}

if ($_SESSION["userSortOrder"] == "name") {
	ksort($data);
} else {
	$data = array_reverse($data, true);
}
unset($output);

render_page($user, $TAB, "list_domain");

// Back uri
$_SESSION["back"] = $_SERVER["REQUEST_URI"];
