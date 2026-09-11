<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/domain/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<?php if (($_SESSION["role"] == "admin" && $accept === "true") || $user_plain !== "admin") { ?>
				<button type="submit" class="button" form="main-form">
					<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml( _("Save")) ?>
				</button>
			<?php } ?>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form
		id="main-form"
		name="v_add_domain"
		method="post"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="ok" value="Add">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Add Domain")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<?php if ($_SESSION["role"] == "admin" && $accept !== "true") { ?>
				<div class="alert alert-danger" role="alert">
					<i class="fas fa-exclamation"></i>
						<p><?= htmlify_trans(
     	sprintf(
     		_("It is strongly advised to {create a standard user account} before adding %s to the server due to the increased privileges the admin account possesses and potential security risks."),
     		_("a domain"),
     	),
     	"</a>",
     	'<a href="/add/user/">',
     ) ?></p>
				</div>
			<?php } ?>
			<?php if ($_SESSION["role"] == "admin" && empty($accept)) { ?>
				<div class="u-side-by-side u-mt20">
					<a href="/add/user/" class="button u-width-full u-mr10"><?= tohtml( _("Add User")) ?></a>
					<a href="/add/domain/?<?= tohtml(http_build_query(["accept" => 'true'])) ?>" class="button button-danger u-width-full u-ml10"><?= tohtml( _("Continue")) ?></a>
				</div>
			<?php } ?>
			<?php if (($_SESSION["role"] == "admin" && $accept === "true") || $_SESSION["role"] !== "admin") { ?>
				<div class="u-mb20">
					<label for="v_domain" class="form-label"><?= tohtml( _("Domain Name")) ?></label>
					<input type="text" class="form-control" name="v_domain" id="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>" required>
				</div>
				<div class="u-mb20">
					<label for="v_targets" class="form-label"><?= tohtml( _("Backend Targets")) ?></label>
					<textarea class="form-control" name="v_targets" id="v_targets" rows="4" placeholder="127.0.0.1:8080 or https://127.0.0.1:8083" required><?= tohtml(trim($v_targets, "'")) ?></textarea>
					<span class="form-check u-mt5 u-text-small u-text-secondary"><?= tohtml( _("One target per line, e.g. 127.0.0.1:8080")) ?></span>
				</div>
				<div class="u-mb20">
					<label for="v_algorithm" class="form-label"><?= tohtml( _("Load Balancing Algorithm")) ?></label>
					<select class="form-select" name="v_algorithm" id="v_algorithm">
						<option value="round_robin" <?php if ($v_algorithm == 'round_robin') echo 'selected'; ?>><?= tohtml( _("Round Robin")) ?></option>
						<option value="weighted" <?php if ($v_algorithm == 'weighted') echo 'selected'; ?>><?= tohtml( _("Weighted")) ?></option>
						<option value="least_conn" <?php if ($v_algorithm == 'least_conn') echo 'selected'; ?>><?= tohtml( _("Least Connections")) ?></option>
						<option value="ip_hash" <?php if ($v_algorithm == 'ip_hash') echo 'selected'; ?>><?= tohtml( _("IP Hash")) ?></option>
						<option value="hash" <?php if ($v_algorithm == 'hash') echo 'selected'; ?>><?= tohtml( _("Hash")) ?></option>
					</select>
				</div>
				<div class="u-mb20">
					<label for="v_dns_provider" class="form-label"><?= tohtml( _("DNS Provider")) ?></label>
					<select class="form-select" name="v_dns_provider" id="v_dns_provider">
						<option value="manual" <?php if ($v_dns_provider == 'manual') echo 'selected'; ?>><?= tohtml( _("Manual")) ?></option>
						<option value="cloudflare" <?php if ($v_dns_provider == 'cloudflare') echo 'selected'; ?> <?php if (empty($dns_providers['cloudflare'])) echo 'disabled'; ?>><?= tohtml( _("Cloudflare")) ?></option>
					</select>
					<?php if (empty($dns_providers['cloudflare'])) { ?>
						<span class="form-check u-mt5 u-text-small u-text-secondary"><?= tohtml( _("An administrator must add a Cloudflare API token before it can be selected.")) ?></span>
					<?php } ?>
				</div>
				<div class="u-mb20">
					<label for="v_ssl" class="form-label"><?= tohtml( _("Enable SSL")) ?></label>
					<select class="form-select" name="v_ssl" id="v_ssl">
						<option value="no" <?php if ($v_ssl == 'no') echo 'selected'; ?>><?= tohtml( _("No")) ?></option>
						<option value="yes" <?php if ($v_ssl == 'yes') echo 'selected'; ?>><?= tohtml( _("Yes")) ?></option>
					</select>
				</div>
			<?php } ?>
		</div>

	</form>

</div>
