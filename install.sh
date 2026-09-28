#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
model_path="${1:-}"

if [[ -z "${model_path}" || "${model_path}" == "-h" || "${model_path}" == "--help" ]]; then
  echo "Usage: ./install.sh /path/to/model.gguf"
  exit 0
fi

for required_command in llama-server curl openssl systemctl omarchy omarchy-shell wl-copy; do
  command -v "${required_command}" >/dev/null 2>&1 || {
    echo "Missing ${required_command}. Install llama.cpp and run this on Omarchy." >&2
    exit 1
  }
done
[[ -f "${model_path}" ]] || { echo "Model not found: ${model_path}" >&2; exit 1; }
model_path="$(realpath "${model_path}")"

plugin_id="io.github.aayush9029.omaai"
plugins_dir="${HOME}/.config/omarchy/plugins"
plugin_installed=false
[[ -f "${plugins_dir}/${plugin_id}/manifest.json" ]] && plugin_installed=true
# Earlier versions installed the widget as local.omaai.
if [[ -d "${plugins_dir}/local.omaai" ]]; then
  omarchy plugin remove local.omaai --yes >/dev/null 2>&1 || rm -rf "${plugins_dir}/local.omaai"
fi

mkdir -p \
  "${HOME}/.local/bin" \
  "${HOME}/.config/omaai" \
  "${HOME}/.config/systemd/user" \
  "${plugins_dir}/${plugin_id}/omarchy"

install -m 0755 "${project_dir}/bin/omaai" "${HOME}/.local/bin/omaai"
install -m 0755 "${project_dir}/bin/omaai-server" "${HOME}/.local/bin/omaai-server"
install -m 0644 "${project_dir}/systemd/omaai.service" "${HOME}/.config/systemd/user/omaai.service"
install -m 0644 "${project_dir}/manifest.json" "${plugins_dir}/${plugin_id}/manifest.json"
install -m 0644 "${project_dir}/omarchy/Panel.qml" "${plugins_dir}/${plugin_id}/omarchy/Panel.qml"

api_key_path="${HOME}/.config/omaai/api-key"
[[ -s "${api_key_path}" ]] || openssl rand -hex 24 >"${api_key_path}"
chmod 0600 "${api_key_path}"

if [[ ! -f "${HOME}/.config/omaai/env" ]]; then
{
  printf 'OMAAI_LLAMA_SERVER=%q\n' "$(command -v llama-server)"
  printf 'OMAAI_MODEL=%q\n' "${model_path}"
  printf 'OMAAI_API_KEY_FILE=%q\n' "${api_key_path}"
  printf 'OMAAI_HOST=127.0.0.1\n'
  printf 'OMAAI_PORT=8080\n'
  printf 'OMAAI_CONTEXT=32768\n'
} >"${HOME}/.config/omaai/env"
fi
chmod 0600 "${HOME}/.config/omaai/env"

systemctl --user daemon-reload
# Preserve the existing on/off preference, including on reinstall.
# A fresh installation stays off until the user turns it on.
if systemctl --user is-active --quiet omaai.service; then
  systemctl --user restart omaai.service
fi
timeout 10s omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if [[ "${plugin_installed}" == false ]]; then
  timeout 10s omarchy plugin enable "${plugin_id}" --section right --before omarchy.monitor >/dev/null 2>&1 || true
fi

echo "OmaAI installed. The power switch remembers your choice across logins. Click the sparkle in the Omarchy bar."
