#!/bin/bash

# Cloudflare DNS provider helpers. Credentials never appear in command arguments.
CF_PROVIDER_DIR="$HESTIA/data/dns-providers"
CF_TOKEN_FILE="$CF_PROVIDER_DIR/cloudflare.token"

cf_error() {
	check_result "$E_INVALID" "Cloudflare DNS provider request failed"
}

cf_token_available() {
	[ -r "$CF_TOKEN_FILE" ] && [ -s "$CF_TOKEN_FILE" ]
}

cf_curl() {
	local method="$1"
	local endpoint="$2"
	local body="$3"
	local config response

	cf_token_available || return 1
	config="$(mktemp)" || return 1
	response="$(mktemp)" || { rm -f "$config"; return 1; }
	chmod 600 "$config" "$response"
	{
		printf 'silent\nshow-error\nfail-with-body\nrequest = "%s"\n' "$method"
		printf 'header = "Authorization: Bearer %s"\n' "$(<"$CF_TOKEN_FILE")"
		printf 'header = "Content-Type: application/json"\n'
		printf 'url = "https://api.cloudflare.com/client/v4%s"\n' "$endpoint"
		[ -n "$body" ] && printf 'data = %s\n' "$(printf '%s' "$body" | jq -c .)"
	} > "$config"
	curl --config "$config" --max-time 20 > "$response" 2>/dev/null
	local status=$?
	rm -f "$config"
	if [ "$status" -ne 0 ] || ! jq -e '.success == true' "$response" >/dev/null 2>&1; then
		rm -f "$response"
		return 1
	fi
	cat "$response"
	rm -f "$response"
}

cf_verify_token() {
	local token_file="$1" response
	[ -s "$token_file" ] || return 1
	response="$(mktemp)" || return 1
	chmod 600 "$response"
	curl --silent --show-error --fail-with-body --max-time 20 \
		--header @<(printf 'Authorization: Bearer %s\n' "$(<"$token_file")") \
		'https://api.cloudflare.com/client/v4/user/tokens/verify' > "$response" 2>/dev/null
	local status=$?
	if [ "$status" -eq 0 ] && jq -e '.success == true' "$response" >/dev/null 2>&1; then
		rm -f "$response"
		return 0
	fi
	rm -f "$response"
	return 1
}

cf_public_ip() {
	local ips ip nat
	ips="$($BIN/v-list-sys-ips json)" || return 1
	ip="$(printf '%s' "$ips" | jq -r 'to_entries[] | select(.value.NAT != null and .value.NAT != "") | .value.NAT' | head -n1)"
	if [ -z "$ip" ] || [ "$ip" = "null" ]; then
		ip="$(printf '%s' "$ips" | jq -r 'keys[]' | head -n1)"
	fi
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
	printf '%s\n' "$ip"
}

cf_ensure_a_record() {
	local fqdn="$1" target="$2" zones zone_id zone_name record_response count record_id current body
	zones='[]'
	local page=1 response page_count
	while :; do
		response="$(cf_curl GET "/zones?per_page=50&page=$page" '')" || return 1
		zones="$(jq -c --argjson existing "$zones" '$existing + .result' <<< "$response")" || return 1
		page_count="$(jq -r '.result_info.total_pages // 1' <<< "$response")"
		[ "$page" -ge "$page_count" ] && break
		page=$((page + 1))
	done
	zone_name="$(jq -r --arg name "$fqdn" '[.[] | . as $zone | select($name == $zone.name or ($name | endswith("." + $zone.name))) | .name] | sort_by(length) | last // empty' <<< "$zones")"
	[ -n "$zone_name" ] || return 1
	zone_id="$(jq -r --arg name "$zone_name" '.[] | select(.name == $name) | .id' <<< "$zones" | head -n1)"
	[ -n "$zone_id" ] || return 1
	record_response="$(cf_curl GET "/zones/$zone_id/dns_records?type=A&name=$fqdn" '')" || return 1
	count="$(jq '.result | length' <<< "$record_response")"
	[ "$count" -le 1 ] || return 1
	if [ "$count" -eq 0 ]; then
		body="$(jq -nc --arg name "$fqdn" --arg content "$target" '{type:"A",name:$name,content:$content,ttl:1,proxied:false}')"
		cf_curl POST "/zones/$zone_id/dns_records" "$body" >/dev/null || return 1
		return 0
	fi
	record_id="$(jq -r '.result[0].id' <<< "$record_response")"
	current="$(jq -r '.result[0].content' <<< "$record_response")"
	[ "$current" = "$target" ] && return 0
	body="$(jq -nc --arg name "$fqdn" --arg content "$target" '{type:"A",name:$name,content:$content,ttl:1,proxied:false}')"
	cf_curl PUT "/zones/$zone_id/dns_records/$record_id" "$body" >/dev/null
}
