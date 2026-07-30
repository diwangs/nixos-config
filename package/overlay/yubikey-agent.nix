# `yubikey-agent` PR #156 to enable Ed25519 signing + AES management key
final: prev:
let
  rev = "59bf94fbe33ed84e89f71f6aefb942ef59ac2a8c";
  version = "0.1.6-unstable-2025-10-26";
  src = prev.fetchFromGitHub {
    owner = "e-nomem";
    repo = "yubikey-agent";
    inherit rev;
    hash = "sha256-LQ2Go/pJgHW2W3bnOD8LcLf8JW93sI70W05FVoTFxco=";
  };
in
{
  yubikey-agent = prev.yubikey-agent.overrideAttrs (old: {
    inherit version src;

    vendorHash = "sha256-w5H6thqDZINcic6jJz6dcGL3+LkR2Iz0UFxwI/vkQsc=";

    # Force AES-192 instead of AES-256 in #156 for `piv-go` compatibility
    # also append `old.postPatch` since it contains `libnotify` patch
    postPatch = old.postPatch + ''
      substituteInPlace setup.go \
        --replace-fail 'key = make([]byte, 32)' 'key = make([]byte, 24)' \
        --replace-fail 'supports AES256 management keys' 'supports AES management keys (we use AES-192; see the overlay)'
    '';

    ldflags = [
      "-s"
      "-w"
      "-X main.Version=${version}"
    ];

    meta = old.meta // {
      changelog = "https://github.com/FiloSottile/yubikey-agent/pull/156";
    };
  });
}
