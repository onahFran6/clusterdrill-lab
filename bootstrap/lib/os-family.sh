#!/usr/bin/env bash
# Sourced by node-common.sh and deploy-appliance.sh (never executed directly)
# to pick which of this directory's per-family libraries (debian.sh, rhel.sh)
# to source next. Detection follows the standard, systemd-project-defined
# /etc/os-release contract (https://www.freedesktop.org/software/systemd/man/os-release.html)
# every mainstream distro ships - no distro-specific tool required.
#
# Kept to exactly this one function: which package-manager family a distro
# belongs to, nothing else. Anything that differs *within* a family (e.g.
# whether EPEL needs enabling on RHEL/Rocky but not Fedora) is the calling
# family library's own problem, decided from the same sourced /etc/os-release
# fields - see rhel.sh.

detect_os_family() {
  # Optional $1 overrides which os-release file to read - real callers never
  # pass it (the default is the real, standard path), but it lets
  # check_os_family_detection.sh exercise this function against synthetic
  # fixture files instead of requiring root or a specific real distro to test
  # the mapping logic itself.
  local os_release_file="${1:-/etc/os-release}"
  # Subshelled and grep'd rather than `source`d into the caller's own
  # environment - os-release files are shell-syntax by contract, but
  # sourcing them directly would leak every field (NAME, VERSION,
  # PRETTY_NAME, ...) into callers that only ever need ID/ID_LIKE.
  local id id_like
  # shellcheck disable=SC1090 # $os_release_file is either the real
  # /etc/os-release or (in tests) a synthetic fixture file - never a fixed
  # path shellcheck could statically follow.
  id="$(. "$os_release_file" && echo "$ID")"
  # shellcheck disable=SC1090 # same as above.
  id_like="$(. "$os_release_file" && echo "${ID_LIKE:-}")"

  case " ${id} ${id_like} " in
    *" ubuntu "*|*" debian "*)
      echo "debian"
      ;;
    *" rhel "*|*" fedora "*|*" rocky "*|*" centos "*|*" almalinux "*)
      echo "rhel"
      ;;
    *)
      echo "os-family: unsupported distro (ID=${id} ID_LIKE=${id_like:-<none>}) - supported families: debian (ubuntu, debian), rhel (rhel, fedora, rocky, centos, almalinux)" >&2
      exit 1
      ;;
  esac
}
