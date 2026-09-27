		</main>
		<?php require $_SERVER["HESTIA"] . "/web/templates/includes/app-footer.php"; ?>
	</div> <?php // Closes `<div class="app">` in header.php ?>
<?php if (
	$_SESSION["userContext"] === "admin" &&
	$_SESSION["POLICY_SYSTEM_HIDE_SERVICES"] !== "yes" &&
	$_SESSION["UPDATE_AVAILABLE"] === "yes"
) {
?>
	<p x-data="{ open: true }" x-cloak x-show="open" class="updates-banner">
		<span class="u-text-bold">New updates are available!</span> To upgrade your server now, run
		<code>apt update && apt upgrade</code> from a shell session.
		(<button type="button" class="u-text-bold" x-on:click="open = false">
			hide
		</button>)
	</p>
<?php } ?>
	<div class="spinner-overlay js-spinner">
		<i class="fas fa-circle-notch fa-spin"></i>
	</div>

	<div x-data>
		<dialog x-ref="dialog" class="shortcuts">
			<div class="shortcuts-header">
				<div class="shortcuts-title"><?= _("Shortcuts") ?></div>
				<div
					x-on:click="$refs.dialog.close()"
					class="shortcuts-close"
				>
					<i class="fas fa-xmark"></i>
				</div>
			</div>
			<div class="shortcuts-inner">
				<ul class="shortcuts-list">
					<li><span class="key">a</span><?= _("Add new object") ?></li>
					<li><span class="key">Ctrl + Enter</span><?= _("Save form") ?></li>
					<li class="u-mb20"><span class="key">Ctrl + Backspace</span><?= _("Unsave form") ?></li>
					<li><span class="key">1</span><?= _("Go to WEB list") ?></li>
					<li><span class="key">2</span><?= _("Go to DNS list") ?></li>
					<li><span class="key">3</span><?= _("Go to MAIL list") ?></li>
					<li><span class="key">4</span><?= _("Go to DB list") ?></li>
					<li><span class="key">5</span><?= _("Go to CRON list") ?></li>
					<li><span class="key">6</span><?= _("Go to BACKUP list") ?></li>
				</ul>
				<ul class="shortcuts-list">
					<li class="u-mb20"><span class="key">f</span><?= _("Focus on search") ?></li>
					<li class="u-mb20"><span class="key">h</span><?= _("Display / Hide shortcuts") ?></li>
					<li><span class="key bigger">&larr;</span><?= _("Move backward through top menu") ?></li>
					<li><span class="key bigger">&rarr;</span><?= _("Move forward through top menu") ?></li>
					<li class="u-mb20"><span class="key">Enter</span><?= _("Enter focused element") ?></li>
					<li><span class="key bigger">&uarr;</span><?= _("Move up through elements list") ?></li>
					<li><span class="key bigger">&darr;</span><?= _("Move down through elements list") ?></li>
				</ul>
			</div>
		</dialog>

		<button
			x-on:click="$refs.dialog.showModal()"
			type="button"
			class="button button-secondary button-circle button-floating button-floating-shortcuts"
			title="<?= _("Shortcuts") ?>"
		>
			<i class="fas fa-keyboard"></i>
			<span class="u-hidden"><?= _("Shortcuts") ?></span>
		</button>
	</div>

	<?php require $_SERVER["HESTIA"] . "/web/templates/includes/jump-to-top-link.php"; ?>

	<script>
		// Hestia-Mini: double-submission guard. Slow operations (DKIM key
		// generation, Exim rebuilds) keep the page responsive long enough to
		// click Save/Delete twice, and the second identical request then fails
		// with a confusing "already exists" / "doesn't exist" error. The first
		// submit/click always goes through; repeats are swallowed.
		(function () {
			function disableSubmitButtons(form) {
				form.querySelectorAll('button[type="submit"], input[type="submit"], button:not([type])').forEach(function (el) {
					el.disabled = true;
				});
				// Toolbar buttons live outside <form> and attach via form="...".
				if (form.id) {
					document.querySelectorAll('[form="' + CSS.escape(form.id) + '"]').forEach(function (el) {
						el.disabled = true;
					});
				}
			}
			document.addEventListener('submit', function (event) {
				var form = event.target;
				if (!(form instanceof HTMLFormElement)) {
					return;
				}
				if (form.dataset.doubleSubmitGuard) {
					event.preventDefault();
					return;
				}
				form.dataset.doubleSubmitGuard = '1';
				disableSubmitButtons(form);
			}, true);
			document.addEventListener('click', function (event) {
				var link = event.target instanceof Element ? event.target.closest('a[href*="/delete/"]') : null;
				if (!link) {
					return;
				}
				if (link.dataset.doubleSubmitGuard) {
					event.preventDefault();
					event.stopPropagation();
					return;
				}
				link.dataset.doubleSubmitGuard = '1';
				// Re-arm after 3s in case navigation was cancelled (e.g. the
				// confirmation dialog was dismissed). A real navigation tears
				// the page down first, so this never unblocks a duplicate.
				setTimeout(function () {
					delete link.dataset.doubleSubmitGuard;
				}, 3000);
			}, true);
		})();
	</script>

</body>
</html>
