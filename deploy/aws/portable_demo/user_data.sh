#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /var/log/user-data-vss.log) 2>&1

REPO_URL="${REPO_URL:-https://github.com/slade208/vssfork.git}"
REPO_BRANCH="${REPO_BRANCH:-steve/cv-overlay-portable}"
REPO_DIR="${REPO_DIR:-/home/ubuntu/vssfork}"

echo "[user-data] starting bootstrap at $(date -u)"

# Show cloud-init progress in SSH login banner (MOTD).
cat > /etc/update-motd.d/99-vss-cloud-init-status <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

status="$(cloud-init status 2>/dev/null || true)"
if [[ "${status}" == "status: running" ]]; then
  echo
  echo "VSS bootstrap: cloud-init is still running user_data setup."
  echo "Check progress: sudo tail -n 120 /var/log/cloud-init-output.log"
  echo
fi
EOF
chmod 0755 /etc/update-motd.d/99-vss-cloud-init-status

wait_for_apt() {
  local retries=60
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [[ $retries -le 0 ]]; then
      echo "[user-data] apt lock timeout"
      return 1
    fi
    echo "[user-data] waiting for apt lock..."
    sleep 5
  done
}

apt_retry() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [[ $n -ge 5 ]]; then
      echo "[user-data] command failed after retries: $*"
      return 1
    fi
    echo "[user-data] retry $n for: $*"
    sleep 10
    wait_for_apt
  done
}

wait_for_apt
apt_retry apt-get update -y
apt_retry apt-get install -y git git-lfs ca-certificates curl jq
git lfs install --system

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "[user-data] cloning ${REPO_URL} -> ${REPO_DIR}"
  mkdir -p "$(dirname "${REPO_DIR}")"
  if [[ "${REPO_URL}" == git@github.com:* ]]; then
    sudo -u ubuntu mkdir -p /home/ubuntu/.ssh
    ssh-keyscan -H github.com | sudo -u ubuntu tee -a /home/ubuntu/.ssh/known_hosts >/dev/null || true
  fi
  if ! sudo -u ubuntu env GIT_TERMINAL_PROMPT=0 git clone "${REPO_URL}" "${REPO_DIR}"; then
    echo "[user-data] clone failed for ${REPO_URL}; trying public HTTPS clone"
    if ! sudo -u ubuntu env GIT_TERMINAL_PROMPT=0 git clone "https://github.com/slade208/vssfork.git" "${REPO_DIR}"; then
      echo "[user-data] git clone still failed; trying GitHub codeload tarball fallback"
      tmpdir="$(mktemp -d)"
      trap 'rm -rf "${tmpdir}"' EXIT
      archive_url="https://codeload.github.com/slade208/vssfork/tar.gz/refs/heads/${REPO_BRANCH}"
      curl -fL "${archive_url}" -o "${tmpdir}/repo.tar.gz"
      mkdir -p "${REPO_DIR}"
      tar -xzf "${tmpdir}/repo.tar.gz" -C "${tmpdir}"
      extracted_dir="$(find "${tmpdir}" -maxdepth 1 -type d -name 'vssfork-*' | head -n 1)"
      cp -a "${extracted_dir}/." "${REPO_DIR}/"
      chown -R ubuntu:ubuntu "${REPO_DIR}"
      rm -rf "${tmpdir}"
      trap - EXIT
    fi
  fi
fi

echo "[user-data] checking out branch ${REPO_BRANCH}"
if [[ -d "${REPO_DIR}/.git" ]]; then
  sudo -u ubuntu git -C "${REPO_DIR}" fetch --all --prune
  sudo -u ubuntu git -C "${REPO_DIR}" checkout "${REPO_BRANCH}" || sudo -u ubuntu git -C "${REPO_DIR}" checkout -b "${REPO_BRANCH}" "origin/${REPO_BRANCH}"
  sudo -u ubuntu git -C "${REPO_DIR}" pull --ff-only || true
  sudo -u ubuntu git -C "${REPO_DIR}" lfs pull || true
else
  echo "[user-data] repo installed from tarball; .git metadata not present"
fi

COMPOSE_DIR="${REPO_DIR}/deploy/docker/remote_vlm_deployment"
mkdir -p "${COMPOSE_DIR}"

if [[ ! -f "${COMPOSE_DIR}/.env" ]]; then
  cat > "${COMPOSE_DIR}/.env.TODO" <<'EOF'
# Copy your real .env to .env before running docker compose.
# Example:
#   cp /path/to/your/.env .env
#
# Then fix host path values for this EC2 machine:
#   sed -i 's#/home/steve/video-search-and-summarization#/home/ubuntu/vssfork#g' .env
EOF
  chown ubuntu:ubuntu "${COMPOSE_DIR}/.env.TODO"
fi

cat > /etc/motd <<'EOF'
VSS demo host is provisioned.

Next:
  cd /home/ubuntu/vssfork/deploy/docker/remote_vlm_deployment
  cp .env.TODO .env  # then replace with your secure .env contents
  docker compose up -d
EOF

echo "[user-data] bootstrap complete at $(date -u)"
