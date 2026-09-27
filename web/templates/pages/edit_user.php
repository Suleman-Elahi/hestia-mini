<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/mail/">
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
		x-data="{
			loginDisabled: <?= tohtml($v_login_disabled === "yes" ? "true" : "false") ?>,
			useIpAllowList: <?= tohtml($v_login_use_iplist === "yes" ? "true" : "false") ?>,
			showAdvanced: false,
		}"
		id="main-form"
		method="post"
		name="v_edit_user"
		class="<?= tohtml($v_status) ?>"
	>
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<input type="hidden" name="save" value="save">

		<div class="form-container">
			<h1 class="u-mb20"><?= tohtml( _("Edit User")) ?></h1>
			<?php show_alert_message($_SESSION); ?>
			<div class="u-mb10">
				<label for="v_user" class="form-label"><?= tohtml( _("Username")) ?></label>
				<input type="text" class="form-control" name="v_user" id="v_user" value="<?= tohtml(trim($v_username, "'")) ?>" disabled required>
				<input type="hidden" name="v_username" value="<?= tohtml(trim($v_username, "'")) ?>">
			</div>
			<div class="u-mb10">
				<label for="v_name" class="form-label"><?= tohtml( _("Contact Name")) ?></label>
				<input type="text" class="form-control" name="v_name" id="v_name" value="<?= tohtml(trim($v_name, "'")) ?>" <?php if (($_SESSION['userContext'] !=='admin' ) && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !=='yes' )) { echo 'disabled' ; }?> required>
				<?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) { ?>
					<input type="hidden" name="v_name" value="<?= tohtml(trim($v_name, "'")) ?>">
				<?php } ?>
			</div>
			<div class="u-mb10">
				<label for="v_email" class="form-label"><?= tohtml( _("Email")) ?></label>
				<input type="email" class="form-control" name="v_email" id="v_email" value="<?= tohtml(trim($v_email, "'")) ?>" <?php if (($_SESSION['userContext'] !=='admin' ) && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !=='yes' )) { echo 'disabled' ; }?> required>
				<?php if (($_SESSION['userContext'] !== 'admin') && ($_SESSION['POLICY_USER_EDIT_DETAILS'] !== 'yes')) { ?>
					<input type="hidden" name="v_email" value="<?= tohtml(trim($v_email, "'")) ?>">
				<?php } ?>
			</div>
			<div class="u-mb10">
				<label for="v_password" class="form-label">
					<?= tohtml( _("Password")) ?>
					<button type="button" title="<?= tohtml( _("Generate")) ?>" class="u-unstyled-button u-ml5 js-generate-password">
						<i class="fas fa-arrows-rotate icon-green"></i>
					</button>
				</label>
				<div class="u-pos-relative u-mb10">
					<input type="text" class="form-control js-password-input" name="v_password" id="v_password" value="<?= tohtml(trim($v_password, "'")) ?>">
					<div class="password-meter">
						<meter max="4" class="password-meter-input js-password-meter"></meter>
					</div>
				</div>
			</div>
			<div id="password-details" class="u-mb20">
				<?php require $_SERVER["HESTIA"] . "/web/templates/includes/password-requirements.php"; ?>
				<?php if ($_SESSION["userContext"] === "admin") { ?>
					<div class="form-check">
						<input x-model="loginDisabled" class="form-check-input" type="checkbox" name="v_login_disabled" id="v_login_disabled">
						<label for="v_login_disabled">
							<?= tohtml( _("Do not allow user to log in to Control Panel")) ?>
						</label>
					</div>
				<?php } ?>
				<div x-cloak x-show="!loginDisabled" id="password-options">
					<div class="form-check">
						<input class="form-check-input" type="checkbox" name="v_twofa" id="v_twofa" <?php if (!empty($v_twofa)) echo 'checked' ?>>
						<label for="v_twofa">
							<?= tohtml( _("Enable two-factor authentication")) ?>
						</label>
					</div>
					<?php if (!empty($v_twofa)) { ?>
						<p class="u-mb10"><?= tohtml( _("Account Recovery Code") . ": " . $v_twofa) ?></p>
						<p class="u-mb10"><?= tohtml( _("Please scan the code below in your 2FA application")) ?>:</p>
						<div class="u-mb10">
							<img class="qr-code" src="<?= tohtml($v_qrcode) ?>" alt="<?= tohtml( _("2FA QR Code")) ?>">
						</div>
					<?php } ?>
				</div>
				<div x-cloak x-show="!loginDisabled" id="password-options-ip">
					<div class="form-check">
						<input x-model="useIpAllowList" class="form-check-input" type="checkbox" name="v_login_use_iplist" id="v_login_use_iplist">
						<label for="v_login_use_iplist">
							<?= tohtml( _("Use IP address allow list for login attempts")) ?>
						</label>
					</div>
				</div>
				<div x-cloak x-show="useIpAllowList" id="ip-allowlist" class="u-mt10">
					<input type="text" class="form-control" name="v_login_allowed_ips" value="<?= tohtml(trim($v_login_allowed_ips, "'")) ?>" placeholder="<?= tohtml( _("For example")) ?>: 127.0.0.1,192.168.1.100">
				</div>
			</div>
			<div class="u-mb10">
				<label for="v_language" class="form-label"><?= tohtml( _("Language")) ?></label>
				<select class="form-select" name="v_language" id="v_language" required>
					<?php
						foreach ($languages as $key => $value) {
							echo "\n\t\t\t\t\t\t\t\t\t<option value=\"".$key."\"";
							$skey = "'".$key."'";
							if (( $key == $v_language ) || ( $skey == $v_language)){
								echo 'selected' ;
							}
							if (( $key == detect_user_language() ) && (empty($v_language))){
								echo 'selected' ;
							}
							echo ">".htmlentities($value)."</option>\n";
						}
					?>
				</select>
			</div>
			<?php if ($_SESSION["POLICY_USER_CHANGE_THEME"] !== "no") { ?>
			<div class="u-mb10">
				<label for="v_user_theme" class="form-label"><?= tohtml( _("Theme")) ?></label>
				<select class="form-select" name="v_user_theme" id="v_user_theme">
					<?php
						foreach ($themes as $key => $value) {
							echo "\t\t\t\t<option value=\"".$value."\"";
							if ((!empty($_SESSION['userTheme'])) && ( $value == $v_user_theme )) {
								echo ' selected' ;
							}
							if ((empty($v_user_theme) && (!empty($_SESSION['THEME']))) && ( $value == $_SESSION['THEME'] )) {
								echo ' selected' ;
							}
							echo ">".$value."</option>\n";
						}
					?>
				</select>
			</div>
			<?php } ?>
				<div class="u-mb10">
					<label for="v_sort_order" class="form-label"><?= tohtml( _("Default List Sort Order")) ?></label>
					<select class="form-select" name="v_sort_order" id="v_sort_order">
						<option value='date' <?php if ($v_sort_order === 'date') echo 'selected' ?>><?= tohtml( _("Date")) ?></option>
						<option value='name' <?php if ($v_sort_order === 'name') echo 'selected' ?>><?= tohtml( _("Name")) ?></option>
					</select>
				</div>
		</div>

	</form>

</div>
