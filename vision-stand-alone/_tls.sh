#!/usr/bin/env bash
# TLS 인증서가 없으면 자체 서명 인증서를 생성한다.
ensure_tls_cert() {
  local tls_dir="${1:-data/vision/certs}"
  local cert_file="${tls_dir}/cert.pem"
  local key_file="${tls_dir}/privkey.pem"
  local host_name host_ip san

  mkdir -p "$tls_dir"
  if [ -s "$cert_file" ] && [ -s "$key_file" ]; then
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    echo "OpenSSL is required to generate TLS certificates. Install openssl or place cert.pem and privkey.pem in ${tls_dir}." >&2
    return 1
  fi

  host_name="$(hostname 2>/dev/null || echo localhost)"
  host_ip=""
  if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  san="DNS:localhost,DNS:${host_name},IP:127.0.0.1"
  case "$host_ip" in
    ''|127.*) ;;
    *.*.*.*) san="${san},IP:${host_ip}" ;;
  esac

  echo "Generating self-signed TLS certificate in ${tls_dir}"
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$key_file" \
    -out "$cert_file" \
    -subj "/CN=${host_name}" \
    -addext "subjectAltName=${san}" >/dev/null 2>&1
  chmod 600 "$key_file"
  chmod 644 "$cert_file"
}
