<?php

$TAB = "TERMINAL";

// Main include
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

if (($_SESSION["WEB_TERMINAL"] ?? "false") !== "true") {
	http_response_code(403);
	exit(_("Web Terminal is disabled."));
}

if (
	$_SESSION["userContext"] === "admin" &&
	$_SESSION["look"] === "admin" &&
	$_SESSION["POLICY_SYSTEM_PROTECTED_ADMIN"] === "yes"
) {
	http_response_code(403);
	exit(_("Web Terminal is unavailable while impersonating the protected administrator."));
}

if ($_SESSION["login_shell"] == "nologin") {
	header("Location: /list/user/");
	exit();
}

// Render page
render_page($user, $TAB, "list_terminal");
