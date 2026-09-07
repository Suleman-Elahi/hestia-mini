<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/domain/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml( _("Back")) ?>
			</a>
		</div>
		<div class="toolbar-buttons">
			<button type="submit" class="button" form="main-form">
				<i class="fas fa-floppy-disk icon-purple"></i><?= tohtml( _("Save")) ?>
			</button>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container">

	<form
		id="main-form"
		name="v_edit_domain"
		method="post"
		class="<?= tohtml($v_status) ?> js-enable-inputs-on-submit"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Edit Domain")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb20">
				<label for="v_domain" class="form-label"><?= tohtml( _("Domain Name")) ?></label>
				<input type="text" class="form-control" name="v_domain" id="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>" disabled required>
				<input type="hidden" name="v_domain" value="<?= tohtml(trim($v_domain, "'")) ?>">
			</div>
			<div class="u-mb20">
				<label for="v_targets" class="form-label"><?= tohtml( _("Backend Targets")) ?></label>
				<textarea class="form-control" name="v_targets" id="v_targets" rows="4" placeholder="127.0.0.1:8080" required><?= tohtml(trim($v_backends, "'")) ?></textarea>
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
				<label for="v_ssl" class="form-label"><?= tohtml( _("Enable SSL")) ?></label>
				<select class="form-select" name="v_ssl" id="v_ssl">
					<option value="no" <?php if ($v_ssl == 'no') echo 'selected'; ?>><?= tohtml( _("No")) ?></option>
					<option value="yes" <?php if ($v_ssl == 'yes') echo 'selected'; ?>><?= tohtml( _("Yes")) ?></option>
				</select>
			</div>
			<?php if (!empty($v_date)) { ?>
				<div class="u-mb20">
					<span class="form-label u-text-secondary">
						<?= tohtml( _("Created")) ?>: <?= tohtml($v_date) ?> <?= tohtml($v_time) ?>
					</span>
				</div>
			<?php } ?>
		</div>

	</form>

</div>
