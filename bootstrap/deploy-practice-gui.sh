#!/usr/bin/env bash
# Installs a minimal practice desktop (XFCE, a terminal, Firefox) on a worker
# node, reachable over noVNC in a plain browser - no VNC client app to
# install. The point is realistic CKAD exam practice: the real PSI/Linux
# Foundation exam is itself delivered as a remote desktop in your browser,
# not a terminal on your own laptop, and practicing locally skips the exact
# latency/control feel worth rehearsing. Written fresh against TigerVNC's and
# noVNC's own public documentation - no text or structure copied from any
# private or course-provided source.
#
# Run on a worker node only, by run.sh, only when PRACTICE_GUI_DEPLOY=1 (see
# run.sh's own "Setting up the practice GUI" stage) and only after worker.sh
# has joined this node to the cluster and run.sh has staged the
# control-plane's kubeconfig at /tmp/admin.conf - see the kubectl section
# below for why.
#
# Debian/Ubuntu-specific (plain apt-get, no lib/os-family.sh dispatch) - the
# only provider this repo builds (providers/aws) always provisions Ubuntu
# 22.04 (see compatibility.json's os block), and unlike node-common.sh's
# containerd/kubelet packages, none of XFCE/TigerVNC/noVNC have an
# RHEL-family equivalent planned here; a future RHEL-family worker path is
# out of scope for this feature, same as practice-tools.sh's own precedent
# for a tool with no cross-family package story.
#
# Idempotent, like every other script in this directory: safe to re-run.
# Re-running re-applies package installs and systemd unit files (cheap,
# apt/systemctl are themselves idempotent) but never rotates the VNC
# password an operator might already be using to connect.
set -euo pipefail

if [ $# -gt 0 ]; then
  echo "usage: $0" >&2
  exit 1
fi

ADMIN_CONF="/tmp/admin.conf"
VNC_PASSWD_FILE="${HOME}/.vnc/passwd"
XSTARTUP_FILE="${HOME}/.vnc/xstartup"
RUN_USER="$(whoami)"

echo "deploy-practice-gui: installing packages (XFCE, TigerVNC, noVNC)"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  xfce4 xfce4-terminal dbus-x11 \
  tigervnc-standalone-server tigervnc-common novnc websockify

# xfce4-screensaver is a Recommends of the xfce4 metapackage, not a hard
# dependency - purged outright, not just configured off. It locks the
# session behind the Linux account's own password, which the `ubuntu` user
# has never had one of (SSH key only) - found by hitting exactly this on a
# real run: an idle session locks itself and there is then no password
# that unlocks it, ever. A locked-out desktop is worse than no screensaver
# at all for a disposable practice lab.
sudo apt-get purge -y -qq xfce4-screensaver

# Firefox specifically from Mozilla's own official apt repo, not Ubuntu's
# plain `firefox` package - that package is just a transitional stub that
# triggers a snap install, and snap's own confinement model requires a
# proper systemd-logind login session to set up the cgroup it expects.
# vncserver never creates one (no display manager, no PAM session), so the
# snap refuses to start at all: `is not a snap cgroup for tag
# snap.firefox.firefox`, found by hitting exactly this on a real run - the
# icon was there, double-clicking did nothing, no error dialog either,
# because snap-confine fails before Firefox's own code ever runs. Mozilla's
# repo ships a real, non-snap binary with no such confinement, specifically
# to sidestep this exact class of problem (documented on their own install
# page). --allow-downgrades matters here too: Ubuntu's transitional stub
# carries an inflated epoch (1:1snap1-...) specifically to make a plain
# `apt install firefox` keep preferring it over a real package of the same
# name - without the flag, apt refuses the real one as a "downgrade".
echo "deploy-practice-gui: installing Firefox from Mozilla's own apt repo (not the Ubuntu snap stub)"
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
  | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
  | sudo tee /etc/apt/preferences.d/mozilla >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq --allow-downgrades firefox

# VNC's wire protocol has no concept of "scroll by N pixels" - a wheel
# scroll is sent as a button click (button 4/5), one per tick. A trackpad's
# inertial scrolling fires a rapid burst of many native wheel events per
# swipe, so the operator's own machine turns each swipe into a burst of
# discrete VNC clicks, and Firefox applies its own per-click scroll
# distance to every single one - found by hitting exactly this on a real
# run: scrolling felt completely uncontrollable, several screens at a time
# per swipe. Firefox's own enterprise-policy mechanism
# (distribution/policies.json, Mozilla's documented location for the repo
# package) dials this back: delta_multiplier_y/x shrink how far each
# individual click-event scrolls, and max_velocity_scale_factor=1 removes
# the extra acceleration Firefox normally layers on top of a fast
# flick/momentum gesture specifically - the exact pattern a trackpad
# produces. "Status": "default" so the operator can still override any of
# these in about:config if they'd rather have it back.
echo "deploy-practice-gui: tuning Firefox's scroll sensitivity for VNC's click-per-tick wheel model"
sudo mkdir -p /usr/lib/firefox/distribution
sudo tee /usr/lib/firefox/distribution/policies.json >/dev/null <<'EOF'
{
  "policies": {
    "Preferences": {
      "general.smoothScroll": { "Value": true, "Status": "default" },
      "mousewheel.default.delta_multiplier_y": { "Value": 40, "Status": "default" },
      "mousewheel.default.delta_multiplier_x": { "Value": 40, "Status": "default" },
      "apz.max_velocity_scale_factor": { "Value": 1, "Status": "default" }
    }
  }
}
EOF

mkdir -p "${HOME}/.vnc" "${HOME}/Desktop"

# A direct desktop icon for each, not a reliance on XFCE's own panel
# buttons/menu entries resolving correctly on their own - the "Web
# Browser" button in particular goes through exo's own separate
# helper-detection layer (~/.config/xfce4/helpers.rc,
# /usr/share/xfce4/helpers/firefox.desktop's X-XFCE-Binaries list), one
# more layer of indirection than a VNC-launched session (no desktop login,
# no PAM/environment.d) reliably exercises the same way a real login does.
# Copying each app's own real desktop file sidesteps that entirely - its
# Exec= line points straight at the real binary.
_add_desktop_icon() {
  local src="$1" dst
  dst="${HOME}/Desktop/$(basename "$1")"
  if [ ! -f "$src" ]; then
    echo "deploy-practice-gui: ${src} not found - skipping this desktop icon" >&2
    return
  fi
  cp -f "$src" "$dst"
  chmod +x "$dst"
  # xfdesktop additionally checks this specific extended attribute before
  # trusting a desktop file enough to launch it on a plain double-click,
  # not just the executable bit - harmless no-op if this xfdesktop version
  # doesn't check it.
  gio set "$dst" metadata::xfce-exe-checksum \
    "$(sha256sum "$dst" | cut -d' ' -f1)" 2>/dev/null || true
}

echo "deploy-practice-gui: adding Firefox and Terminal icons to the desktop"
_add_desktop_icon /usr/share/applications/firefox.desktop
_add_desktop_icon /usr/share/applications/xfce4-terminal.desktop

# vncpasswd -f reads one password from stdin and writes TigerVNC's own
# encoded form to stdout - no confirmation prompt, suitable for a
# non-interactive script. Classic VNC auth only uses the first 8 characters
# of whatever password is set, so generating exactly 8 avoids a password
# that silently behaves shorter than it looks.
if [ -f "$VNC_PASSWD_FILE" ]; then
  echo "deploy-practice-gui: reusing the existing VNC password from a previous run"
  VNC_PASSWORD_PRINTED=0
else
  echo "deploy-practice-gui: generating a new VNC password"
  VNC_PASSWORD="$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | cut -c1-8)"
  echo "$VNC_PASSWORD" | vncpasswd -f > "$VNC_PASSWD_FILE"
  chmod 600 "$VNC_PASSWD_FILE"
  VNC_PASSWORD_PRINTED=1
fi

# startxfce4 is the one line that matters for which desktop a vncserver
# session launches - the XDG_DATA_DIRS export above it matters just as
# much, for a less obvious reason. A real desktop login picks up
# /var/lib/snapd/desktop (where the firefox snap's own, visible .desktop
# file lives) via systemd's environment.d/PAM integration - a vncserver
# session goes through neither, so without this export XDG_DATA_DIRS stays
# at its plain default (/usr/local/share:/usr/share) and Firefox's menu
# entry is invisible: the only firefox.desktop that default actually finds
# is apt's own transitional-package stub, which is deliberately
# NoDisplay=true (found by hitting exactly this on a real run - Firefox
# installed and working, but absent from every menu).
cat > "$XSTARTUP_FILE" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_DATA_DIRS="/var/lib/snapd/desktop:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec startxfce4
EOF
chmod +x "$XSTARTUP_FILE"

echo "deploy-practice-gui: configuring the VNC server (display :1, localhost-only)"
# -localhost yes matters: it binds Xvnc itself to 127.0.0.1 only, never
# reachable directly from outside this node. The websockify proxy below is
# the only port ever exposed externally - see providers/aws/main.tf's
# practice_gui security-group rule, which only opens 6080, not 5901.
#
# Type=simple + -fg, not Type=forking + PIDFile: TigerVNC's own vncserver
# wrapper names its PID file "<fqdn>:<port>.pid" (port, not display number;
# FQDN, not the short hostname systemd's %H specifier gives you), so a
# PIDFile= guess built from %H and the display number never matches the
# real file - found by hitting it on a real run, not in theory. -fg (added
# to TigerVNC specifically for systemd integration) keeps the wrapper
# attached in the foreground instead, so systemd tracks the real process
# directly and needs no PID file at all.
sudo tee /etc/systemd/system/practice-vnc.service >/dev/null <<EOF
[Unit]
Description=TigerVNC server for the CKAD practice desktop (display :1)
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${HOME}
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStart=/usr/bin/vncserver :1 -fg -localhost yes -geometry 1280x800 -depth 24
ExecStopPost=-/usr/bin/vncserver -kill :1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "deploy-practice-gui: configuring the noVNC/websockify proxy (6080 -> 5901)"
# --web serves noVNC's own static vnc.html/JS alongside the websocket proxy
# in the same process - the one command noVNC's own docs recommend for
# exactly this setup (the same thing its utils/novnc_proxy wrapper does).
sudo tee /etc/systemd/system/practice-novnc.service >/dev/null <<EOF
[Unit]
Description=noVNC websocket proxy for the CKAD practice desktop (6080 -> 5901)
After=practice-vnc.service
Requires=practice-vnc.service

[Service]
Type=simple
User=${RUN_USER}
ExecStart=/usr/bin/websockify --web /usr/share/novnc 6080 localhost:5901
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable practice-vnc.service practice-novnc.service >/dev/null
sudo systemctl restart practice-vnc.service
sudo systemctl restart practice-novnc.service

# Without this, a terminal inside the practice desktop can't run kubectl at
# all, which defeats the point - the real exam environment comes with
# kubectl already pointed at the cluster under test. admin.conf is already
# owned by this same SSH user (run.sh scp'd it here as that user), so no
# sudo is needed, unlike control-plane.sh's equivalent copy from the
# root-owned /etc/kubernetes/admin.conf.
if [ ! -f "$ADMIN_CONF" ]; then
  echo "deploy-practice-gui: $ADMIN_CONF not found - run.sh stages it from the control-plane's kubeconfig before calling this script" >&2
  exit 1
fi
echo "deploy-practice-gui: setting up kubectl access for ${RUN_USER}"
mkdir -p "${HOME}/.kube"
cp -f "$ADMIN_CONF" "${HOME}/.kube/config"
chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

echo "deploy-practice-gui: done"
if [ "$VNC_PASSWORD_PRINTED" -eq 1 ]; then
  echo "VNC password: ${VNC_PASSWORD}"
else
  echo "VNC password: unchanged - already set in ${VNC_PASSWD_FILE} from a previous run"
fi
