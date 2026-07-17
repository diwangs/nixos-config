operation="$1"
mask="$2"

firmware_code=1
secure_boot=2

unlock_mask() {
	local target_mask="$1"
	local rc=0

	if ((target_mask & firmware_code)); then
		if ! "$PCRLOCK" unlock-firmware-code; then
			rc=1
		fi
	fi
	if ((target_mask & secure_boot)); then
		if ! "$PCRLOCK" unlock-secureboot-policy; then
			rc=1
		fi
		if ! "$PCRLOCK" unlock-secureboot-authority; then
			rc=1
		fi
	fi
	return "$rc"
}

lock_mask() {
	local target_mask="$1"
	local rc=0

	if ((target_mask & firmware_code)); then
		if ! "$PCRLOCK" lock-firmware-code; then
			rc=1
		fi
	fi
	if ((target_mask & secure_boot)); then
		if ! "$PCRLOCK" lock-secureboot-policy; then
			rc=1
		fi
		if ! "$PCRLOCK" lock-secureboot-authority; then
			rc=1
		fi
	fi
	return "$rc"
}

refresh_policy() {
	"$SYSTEMCTL" restart systemd-pcrlock-make-policy.service
}

case "$operation" in
	prepare)
		unlock_mask "$mask" && refresh_policy
		;;
	restore)
		rc=0
		if ! lock_mask "$mask"; then
			rc=1
		fi
		if ! refresh_policy; then
			rc=1
		fi
		exit "$rc"
		;;
	*)
		echo "usage: fwupd-pcrlock-helper {prepare|restore} MASK" >&2
		exit 2
		;;
esac
