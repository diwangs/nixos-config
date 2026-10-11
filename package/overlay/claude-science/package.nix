# Claude Science (beta), repackaged from Anthropic's prebuilt Linux binary —
# https://claude.com/product/claude-science
#
# Upstream's installer (https://claude.ai/install-claude-science.sh) reads a
# release bucket laid out as:
#   <base>/latest                — bare sha8 pointer to the newest release
#   <base>/<sha8>/manifest.json  — {"version", "sha256":{<platform>:<hex>}}
#   <base>/<sha8>/operon-<plat>  — the binary
# We pin the immutable per-sha8 URL rather than the moving
# downloads.claude.ai/claude-science/latest/linux-x64 redirect.
#
# The binary is a Bun single-file executable (glibc, /lib64 interpreter): the
# JS bundle is a trailer appended to the ELF. autoPatchelfHook rewrites the
# interpreter; `dontStrip` keeps strip from dropping the trailer (same as
# nixpkgs' claude-code-bin).
#
# FHS: the daemon assumes an FHS host. It runs helpers (`mkdir`, ...) with a
# hard-coded PATH=/usr/bin:/bin, and picks bash from pinned paths (/bin/bash,
# /usr/bin/bash, /run/current-system/sw/bin/bash). Its bwrap sandbox only
# mounts /usr, /lib, /lib64, /bin, /sbin, /opt and /nix, so on NixOS neither
# lookup resolves inside it ("mkdir ...: execvp: No such file or directory"
# breaking the micromamba install for Python/R, and exit 127 from the MCP env
# probe). Running it in buildFHSEnv puts real tools under /usr/bin and /bin,
# which that sandbox does mount. The FHS env also provides the glibc loader
# that conda-forge binaries expect.
#
# CA certificates: that sandbox also ro-binds /etc/ssl, but in buildFHSEnv
# /etc/ssl/certs is a symlink to /.host-etc/ssl/certs, whose files point on to
# /etc/static — neither of which the sandbox mounts, so libmamba (and anything
# else in the sandbox) saw no CA bundle. We bind a store directory over
# /etc/ssl whose files resolve straight into /nix/store. It carries nixpkgs'
# cacert, which matches the host bundle as long as NixOS adds no custom CAs
# (`security.pki.*`).
#
# The daemon (`claude-science serve`, used from a browser) self-updates by
# replacing its own executable, which is read-only in the store. The launcher
# forces `serve --no-auto-update`; updates come through ./update.sh instead.
# `serve` detaches the daemon, so the FHS env must not kill its children when
# the launcher exits (`dieWithParent = false`).
#
# Runtime: the sandbox needs `bwrap` (>= 0.8, --disable-userns) and `socat`,
# and `xdg-open` opens the browser. bwrap needs unprivileged user namespaces,
# which the hardened kernel disables by default (enabled in
# ../../../aspect/virtualisation.nix).
#
# Version, sha8 and hash are PINNED below and maintained by ./update.sh — do
# not edit the three UPDATE MARKER lines by hand.
#
# Last updated: 081026
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  buildFHSEnv,
  writeShellScript,
  runCommandLocal,
  cacert,
}:
let
  base = "https://storage.googleapis.com/operon-dist-cf94a20e-f71c-413c-bd00-9e12b1fedf59/operon-releases";
  sha8 = "8db2454a"; # UPDATE MARKER: sha8
  version = "0.1.60"; # UPDATE MARKER: version

  src = fetchurl {
    url = "${base}/${sha8}/operon-linux-x64";
    hash = "sha256-lMf5xQqopHk1zHVNLks7fXyxhu9I5IJt81OZcyIAMQg="; # UPDATE MARKER: hash
  };

  meta = {
    description = "Research workbench for science built on Claude (repackaged prebuilt binary)";
    homepage = "https://claude.com/product/claude-science";
    downloadPage = "https://claude.com/product/claude-science";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-science";
  };

  unwrapped = stdenv.mkDerivation {
    pname = "claude-science-unwrapped";
    inherit version src meta;

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    # Stripping drops the appended Bun payload (see header comment).
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/claude-science
      runHook postInstall
    '';
  };

  # Not makeWrapper: the flag must be injected only for the `serve`
  # subcommand, which is the only one that accepts it.
  launcher = writeShellScript "claude-science-launcher" ''
    if [ "''${1:-}" = serve ]; then
      shift
      exec ${unwrapped}/bin/claude-science serve --no-auto-update "$@"
    fi
    exec ${unwrapped}/bin/claude-science "$@"
  '';

  # /etc/ssl with the bundle under every name the app and libmamba probe
  # (see header comment).
  etcSsl = runCommandLocal "claude-science-etc-ssl" { } ''
    mkdir -p $out/certs
    bundle=${cacert}/etc/ssl/certs/ca-bundle.crt
    ln -s $bundle $out/certs/ca-certificates.crt
    ln -s $bundle $out/certs/ca-bundle.crt
    ln -s $bundle $out/cert.pem
    ln -s $bundle $out/ca-bundle.pem
  '';
in
buildFHSEnv {
  pname = "claude-science";
  inherit version meta;

  # buildFHSEnv's base set already provides bash, coreutils, findutils,
  # gnugrep, gnused, gawk, gnutar, gzip, bzip2 and xz under /usr/bin and /bin.
  targetPkgs =
    pkgs: with pkgs; [
      unwrapped
      bubblewrap # sandbox
      socat # sandbox networking bridges
      xdg-utils # xdg-open to launch the browser
      procps # ps, probed at /bin/ps and /usr/bin/ps
      which
      curl
      git
      openssh # SSH compute targets
    ];

  # Comes after buildFHSEnv's own /etc symlinks, so it covers the
  # /etc/ssl/certs -> /.host-etc link.
  extraBwrapArgs = [ "--ro-bind ${etcSsl} /etc/ssl" ];

  runScript = launcher;

  # `serve` forks a detached daemon that must outlive the launcher.
  dieWithParent = false;

  passthru = { inherit unwrapped; };
}
