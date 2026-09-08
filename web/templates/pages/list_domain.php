<?php
	$search_query = $_GET['q'] ?? '';
	if (!is_scalar($search_query)) {
		http_response_code(400);
		echo tohtml(sprintf(_("Bad Request: parameter q must be scalar, got %s."), gettype($search_query)));
		return;
	}
	$search_query = (string) $search_query;
?>
<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<?php if ($read_only !== "true") { ?>
				<a href="/add/domain/" class="button button-secondary js-button-create">
					<i class="fas fa-circle-plus icon-green"></i><?= tohtml( _("Add Domain")) ?>
				</a>
				<?php if (($_SESSION["userContext"] ?? "") === "admin") { ?>
					<button type="button" class="button button-secondary" onclick="document.getElementById('cloudflare-provider-dialog').showModal()">
						<i class="fas fa-cloud icon-orange"></i><?= tohtml(_("Add DNS Provider")) ?>
					</button>
				<?php } ?>
			<?php } ?>
		</div>
		<div class="toolbar-right">
			<div class="toolbar-sorting">
				<button class="toolbar-sorting-toggle js-toggle-sorting-menu" type="button" title="<?= tohtml( _("Sort items")) ?>">
					<?= tohtml( _("Sort by")) ?>:
					<span class="u-text-bold">
						<?php if ($_SESSION['userSortOrder'] === 'name') { $label = _('Name'); } else { $label = _('Date'); } ?>
						<?= tohtml($label) ?> <i class="fas fa-arrow-down-a-z"></i>
					</span>
				</button>
				<ul class="toolbar-sorting-menu js-sorting-menu u-hidden">
					<li data-entity="sort-name">
						<span class="name <?php if ($_SESSION['userSortOrder'] === 'name') { echo 'active'; } ?>"><?= tohtml( _("Name")) ?> <i class="fas fa-arrow-down-a-z"></i></span><span class="up"><i class="fas fa-arrow-up-a-z"></i></span>
					</li>
					<li data-entity="sort-date" data-sort-as-int="1">
						<span class="name <?php if ($_SESSION['userSortOrder'] === 'date') { echo 'active'; } ?>"><?= tohtml( _("Date")) ?> <i class="fas fa-arrow-down-a-z"></i></span><span class="up"><i class="fas fa-arrow-up-a-z"></i></span>
					</li>
				</ul>
				<?php if ($read_only !== "true") { ?>
					<form x-data x-bind="BulkEdit" action="/bulk/domain/" method="post">
						<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
						<select class="form-select" name="action">
							<option value=""><?= tohtml( _("Apply to selected")) ?></option>
							<option value="suspend"><?= tohtml( _("Suspend")) ?></option>
							<option value="unsuspend"><?= tohtml( _("Unsuspend")) ?></option>
							<option value="delete"><?= tohtml( _("Delete")) ?></option>
						</select>
						<button type="submit" class="toolbar-input-submit" title="<?= tohtml( _("Apply to selected")) ?>">
							<i class="fas fa-arrow-right"></i>
						</button>
					</form>
				<?php } ?>
			</div>
			<div class="toolbar-search">
				<form action="/search/" method="get">
					<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
					<input type="search" class="form-control js-search-input" name="q" value="<?= tohtml($search_query) ?>" title="<?= tohtml( _("Search")) ?>">
					<button type="submit" class="toolbar-input-submit" title="<?= tohtml( _("Search")) ?>">
						<i class="fas fa-magnifying-glass"></i>
					</button>
				</form>
			</div>
		</div>
	</div>
</div>
<!-- End toolbar -->

<?php if (($_SESSION["userContext"] ?? "") === "admin" && $read_only !== "true") { ?>
<dialog id="cloudflare-provider-dialog">
	<form action="/add/dns-provider/" method="post">
		<input type="hidden" name="token" value="<?= tohtml($_SESSION["token"]) ?>">
		<h2><?= tohtml(_("Add DNS Provider")) ?></h2>
		<div class="u-mb20">
			<label for="cloudflare_token" class="form-label"><?= tohtml(_("Cloudflare API Token")) ?></label>
			<input type="password" class="form-control" name="cloudflare_token" id="cloudflare_token" autocomplete="new-password" required>
			<span class="form-check u-mt5 u-text-small u-text-secondary"><?= tohtml(_("Cloudflare verifies this token before saving it.")) ?></span>
		</div>
		<button type="submit" class="button"><?= tohtml(_("Save Cloudflare")) ?></button>
		<button type="button" class="button button-secondary" onclick="this.closest('dialog').close()"><?= tohtml(_("Cancel")) ?></button>
	</form>
</dialog>
<?php } ?>

<div class="container">

	<h1 class="u-text-center u-hide-desktop u-mt20 u-pr30 u-mb20 u-pl30"><?= tohtml( _("Domains")) ?></h1>

	<div class="units-table js-units-container">
		<div class="units-table-header">
			<div class="units-table-cell">
				<input type="checkbox" class="js-toggle-all-checkbox" title="<?= tohtml( _("Select all")) ?>" <?= tohtml($display_mode) ?>>
			</div>
			<div class="units-table-cell"><?= tohtml( _("Name")) ?></div>
			<div class="units-table-cell"></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("Algorithm")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("Backends")) ?></div>
			<div class="units-table-cell u-text-center"><?= tohtml( _("SSL")) ?></div>
		</div>

		<!-- Begin domain list item loop -->
		<?php
			if (!is_array($data)) {
				$data = [];
			}
			$i = 0;
			foreach ($data as $key => $value) {
				++$i;
				$domain_type = $data[$key]['TYPE'] ?? 'proxy';
				$is_proxy_domain = $domain_type !== 'mail';
				$is_mail_domain = $domain_type !== 'proxy';
				$domain_url = $is_proxy_domain
					? '/edit/domain/?' . http_build_query(["domain" => $key, "token" => $_SESSION["token"]])
					: '/list/mail/?' . http_build_query(["domain" => $key, "token" => $_SESSION["token"]]);
				$domain_action_title = $is_proxy_domain ? _('Edit Domain') : _('Mail Accounts');
				if ($data[$key]['SUSPENDED'] == 'yes') {
					$status = 'suspended';
					$spnd_action = 'unsuspend';
					$spnd_action_title = _('Unsuspend');
					$spnd_icon = 'fa-play';
					$spnd_icon_class = 'icon-green';
					$spnd_confirmation = _('Are you sure you want to unsuspend domain %s?');
				} else {
					$status = 'active';
					$spnd_action = 'suspend';
					$spnd_action_title = _('Suspend');
					$spnd_icon = 'fa-pause';
					$spnd_icon_class = 'icon-highlight';
					$spnd_confirmation = _('Are you sure you want to suspend domain %s?');
				}
				if ($data[$key]['SSL'] == 'no') {
					$ssl_icon = 'fa-circle-xmark';
					$ssl_icon_class = ($status == 'suspended') ? '' : 'icon-red';
					$ssl_title = _('Disabled');
				} else {
					$ssl_icon = 'fa-circle-check';
					$ssl_icon_class = ($status == 'suspended') ? '' : 'icon-green';
					$ssl_title = _('Enabled');
				}
				$algorithm = $is_proxy_domain ? ($data[$key]['ALGORITHM'] ?? 'round_robin') : _('Mail');
				$backends = $is_proxy_domain ? ($data[$key]['TARGETS'] ?? '') : '—';
				if (is_array($backends)) {
					$backends = implode(', ', $backends);
				}
			?>
			<div class="units-table-row <?php if ($status == 'suspended') echo 'disabled'; ?> js-unit"
				data-sort-date="<?= tohtml(strtotime($data[$key]['DATE'].' '.$data[$key]['TIME'])) ?>"
				data-sort-name="<?= tohtml($key) ?>">
				<div class="units-table-cell">
					<div>
						<input id="check<?= tohtml($i) ?>" class="js-unit-checkbox" type="checkbox" title="<?= tohtml( _("Select")) ?>" name="domain[]" value="<?= tohtml($key) ?>" <?= tohtml($display_mode) ?><?= $is_proxy_domain ? '' : ' disabled' ?>>
						<label for="check<?= tohtml($i) ?>" class="u-hide-desktop"><?= tohtml( _("Select")) ?></label>
					</div>
				</div>
				<div class="units-table-cell units-table-heading-cell u-text-bold">
					<span class="u-hide-desktop"><?= tohtml( _("Name")) ?>:</span>
					<a href="<?= tohtml($domain_url) ?>" title="<?= tohtml($domain_action_title) ?>: <?= tohtml($key) ?>">
						<?= tohtml($key) ?>
					</a>
				</div>
				<div class="units-table-cell">
					<ul class="units-table-row-actions">
						<?php if ($is_proxy_domain) { ?>
						<?php if ($read_only !== "true") { ?>
							<?php if ($data[$key]["SUSPENDED"] == "no") { ?>
								<li class="units-table-row-action shortcut-enter" data-key-action="href">
									<a
										class="units-table-row-action-link"
										href="/edit/domain/?<?= tohtml(http_build_query(["domain" => $key, "token" => $_SESSION["token"]])) ?>"
										title="<?= tohtml( _("Edit Domain")) ?>"
									>
										<i class="fas fa-pencil icon-orange"></i>
										<span class="u-hide-desktop"><?= tohtml( _("Edit Domain")) ?></span>
									</a>
								</li>
							<?php } ?>
							<li class="units-table-row-action shortcut-s" data-key-action="js">
								<a
									class="units-table-row-action-link data-controls js-confirm-action"
									href="/<?= tohtml($spnd_action) ?>/domain/?<?= tohtml(http_build_query(["domain" => $key, "token" => $_SESSION["token"]])) ?>"
									title="<?= tohtml($spnd_action_title) ?>"
									data-confirm-title="<?= tohtml($spnd_action_title) ?>"
									data-confirm-message="<?= tohtml(sprintf($spnd_confirmation, $key)) ?>"
								>
									<i class="fas <?= tohtml($spnd_icon) ?> <?= tohtml($spnd_icon_class) ?>"></i>
									<span class="u-hide-desktop"><?= tohtml($spnd_action_title) ?></span>
								</a>
							</li>
							<li class="units-table-row-action shortcut-delete" data-key-action="js">
								<a
									class="units-table-row-action-link data-controls js-confirm-action"
									href="/delete/domain/?<?= tohtml(http_build_query(["domain" => $key, "token" => $_SESSION["token"]])) ?>"
									title="<?= tohtml( _("Delete")) ?>"
									data-confirm-title="<?= tohtml( _("Delete")) ?>"
									data-confirm-message="<?= tohtml(sprintf(_("Are you sure you want to delete domain %s?"), $key)) ?>"
								>
									<i class="fas fa-trash icon-red"></i>
									<span class="u-hide-desktop"><?= tohtml( _("Delete")) ?></span>
								</a>
							</li>
						<?php } ?>
						<?php } ?>
					</ul>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Algorithm")) ?>:</span>
					<?= tohtml($algorithm) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("Backends")) ?>:</span>
					<?= tohtml($backends) ?>
				</div>
				<div class="units-table-cell u-text-center-desktop">
					<span class="u-hide-desktop u-text-bold"><?= tohtml( _("SSL")) ?>:</span>
					<i class="fas <?= tohtml($ssl_icon) ?> <?= tohtml($ssl_icon_class) ?>" title="<?= tohtml($ssl_title) ?>"></i>
				</div>
			</div>
		<?php } ?>
	</div>

	<div class="units-table-footer">
		<p>
			<?php printf(ngettext("%d domain", "%d domains", $i), $i); ?>
		</p>
	</div>

</div>
