#!/usr/bin/env bash
#
# generate-kafka-certs.sh
#
# Production-grade certificate generator for Apache Kafka 4.x (KRaft mode)
# using an existing internal Certificate Authority.
#
# Usage: ./generate-kafka-certs.sh
#
# Requires: openssl, keytool, java
# Reads configuration from: config.env (in the same directory as the script)
#
# Environment Variables:
#   FORCE=true    Overwrite existing output files (default: abort if files exist)
#
# shellcheck shell=bash
# shellcheck disable=SC2317

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# =============================================================================
# GLOBALS
# =============================================================================

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Temporary directory for secure file operations
TEMP_DIR=""

# Parsed configuration values
# We use a flat file approach instead of associative array for POSIX compatibility
# in the parser, but we use associative array for runtime (Bash 4+)
declare -A CONFIG=()

# =============================================================================
# LOGGING
# =============================================================================

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_BOLD='\033[1m'

log_info()    { printf "${C_BLUE}[INFO]${C_RESET}    %s\n" "$*"; }
log_success() { printf "${C_GREEN}[SUCCESS]${C_RESET} %s\n" "$*"; }
log_warning() { printf "${C_YELLOW}[WARNING]${C_RESET} %s\n" "$*" >&2; }
log_error()   { printf "${C_RED}[ERROR]${C_RESET}   %s\n" "$*" >&2; }

log_fatal() {
    printf "${C_RED}${C_BOLD}[FATAL]${C_RESET}   %s\n" "$*" >&2
    exit 1
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup() {
    local exit_code=$?
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
    exit "${exit_code}"
}

trap cleanup EXIT ERR INT TERM

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

assert_file_readable() {
    local file="$1"
    local desc="$2"
    if [[ ! -f "${file}" ]]; then
        log_fatal "${desc} not found: ${file}"
    fi
    if [[ ! -r "${file}" ]]; then
        log_fatal "${desc} is not readable: ${file}"
    fi
}

assert_dir_writable() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        log_info "Creating output directory: ${dir}"
        mkdir -p "${dir}" || log_fatal "Failed to create directory: ${dir}"
    fi
    if [[ ! -w "${dir}" ]]; then
        log_fatal "Output directory is not writable: ${dir}"
    fi
}

assert_not_empty() {
    local value="$1"
    local name="$2"
    if [[ -z "${value}" ]]; then
        log_fatal "Configuration value must not be empty: ${name}"
    fi
}

assert_numeric() {
    local value="$1"
    local name="$2"
    if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
        log_fatal "Configuration value must be numeric: ${name}=${value}"
    fi
}

assert_rsa_bits() {
    local bits="$1"
    case "${bits}" in
        2048|3072|4096)
            ;;
        *)
            log_fatal "RSA_BITS must be one of: 2048, 3072, 4096. Got: ${bits}"
            ;;
    esac
}

# =============================================================================
# CONFIGURATION PARSER
# =============================================================================

parse_config() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        log_fatal "Configuration file not found: ${config_file}"
    fi
    if [[ ! -r "${config_file}" ]]; then
        log_fatal "Configuration file is not readable: ${config_file}"
    fi

    log_info "Parsing configuration file: ${config_file}"

    local line_num=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line_num=$((line_num + 1))

        # Skip empty lines
        [[ -z "${line}" ]] && continue

        # Skip lines that are only whitespace
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue

        # Skip comment lines (must start with # after optional whitespace)
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue

        # Validate KEY=VALUE format: key must start with letter or underscore,
        # followed by letters, digits, or underscores
        if [[ ! "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
            log_fatal "Malformed configuration at line ${line_num}: ${line}"
        fi

        # Extract key and value
        local key="${line%%=*}"
        local value="${line#*=}"

        # Trim trailing whitespace from key
        key="$(printf '%s' "${key}" | sed 's/[[:space:]]*$//')"

        # Store in associative array
        CONFIG["${key}"]="${value}"

    done < "${config_file}"

    log_success "Configuration parsed successfully (${line_num} lines processed)"
}

config_get() {
    local key="$1"
    local default="${2:-}"
    printf '%s' "${CONFIG[${key}]:-${default}}"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_environment() {
    log_info "Validating environment..."

    if ! command_exists openssl; then
        log_fatal "OpenSSL is not installed or not in PATH"
    fi
    log_success "OpenSSL found: $(openssl version | awk '{print $1" "$2}')"

    if ! command_exists java; then
        log_fatal "Java is not installed or not in PATH"
    fi
    log_success "Java found: $(java -version 2>&1 | head -n1 | sed 's/"//g')"

    if ! command_exists keytool; then
        log_fatal "keytool is not installed or not in PATH"
    fi
    log_success "keytool found"

    log_success "Environment validation passed"
}

validate_config() {
    log_info "Validating configuration values..."

    assert_not_empty "$(config_get CA_CERT)" "CA_CERT"
    assert_not_empty "$(config_get CA_KEY)" "CA_KEY"
    assert_not_empty "$(config_get OUTPUT_DIR)" "OUTPUT_DIR"

    assert_not_empty "$(config_get KEYSTORE_PASSWORD)" "KEYSTORE_PASSWORD"
    assert_not_empty "$(config_get TRUSTSTORE_PASSWORD)" "TRUSTSTORE_PASSWORD"
    assert_not_empty "$(config_get KEY_PASSWORD)" "KEY_PASSWORD"

    local rsa_bits
    rsa_bits="$(config_get RSA_BITS "3072")"
    assert_rsa_bits "${rsa_bits}"

    local valid_days
    valid_days="$(config_get VALID_DAYS "365")"
    assert_numeric "${valid_days}" "VALID_DAYS"

    assert_file_readable "$(config_get CA_CERT)" "CA certificate"
    assert_file_readable "$(config_get CA_KEY)" "CA private key"

    assert_dir_writable "$(config_get OUTPUT_DIR)"

    # At least one DNS SAN must exist
    local has_dns=false
    local key
    for key in "${!CONFIG[@]}"; do
        if [[ "${key}" =~ ^SERVER_DNS_[0-9]+$ ]]; then
            has_dns=true
            break
        fi
    done

    if [[ "${has_dns}" == false ]]; then
        log_fatal "At least one SERVER_DNS_* entry is required in config.env"
    fi

    log_success "Configuration validation passed"
}

# =============================================================================
# CERTIFICATE SUBJECT HELPERS
# =============================================================================

build_subject() {
    local cn="$1"
    local subject="/CN=${cn}"

    local country state locality org ou email
    country="$(config_get COUNTRY "")"
    state="$(config_get STATE "")"
    locality="$(config_get LOCALITY "")"
    org="$(config_get ORGANIZATION "")"
    ou="$(config_get ORGANIZATIONAL_UNIT "")"
    email="$(config_get EMAIL "")"

    [[ -n "${country}" ]] && subject="${subject}/C=${country}"
    [[ -n "${state}" ]] && subject="${subject}/ST=${state}"
    [[ -n "${locality}" ]] && subject="${subject}/L=${locality}"
    [[ -n "${org}" ]] && subject="${subject}/O=${org}"
    [[ -n "${ou}" ]] && subject="${subject}/OU=${ou}"
    [[ -n "${email}" ]] && subject="${subject}/emailAddress=${email}"

    printf '%s' "${subject}"
}

# =============================================================================
# SAN GENERATION
# =============================================================================

generate_san_config() {
    local san_file="$1"
    local is_server="$2"

    {
        printf "[req]\n"
        printf "distinguished_name = req_distinguished_name\n"
        printf "req_extensions = v3_req\n"
        printf "prompt = no\n"
        printf "[req_distinguished_name]\n"
        printf "[v3_req]\n"
        printf "keyUsage = keyEncipherment, dataEncipherment, digitalSignature\n"
        if [[ "${is_server}" == "true" ]]; then
            printf "extendedKeyUsage = serverAuth\n"
        else
            printf "extendedKeyUsage = clientAuth\n"
        fi
        printf "subjectAltName = @alt_names\n"
        printf "[alt_names]\n"

        local idx=1
        local key
        for key in "${!CONFIG[@]}"; do
            if [[ "${key}" =~ ^SERVER_DNS_[0-9]+$ ]]; then
                printf "DNS.%d = %s\n" "${idx}" "${CONFIG[${key}]}"
                ((idx++))
            fi
        done

        idx=1
        for key in "${!CONFIG[@]}"; do
            if [[ "${key}" =~ ^SERVER_IP_[0-9]+$ ]]; then
                printf "IP.%d = %s\n" "${idx}" "${CONFIG[${key}]}"
                ((idx++))
            fi
        done
    } > "${san_file}"
}

# =============================================================================
# CERTIFICATE GENERATION
# =============================================================================

generate_server_cert() {
    log_info "Generating server certificate..."

    local output_dir rsa_bits valid_days ca_cert ca_key server_cn key_pass
    output_dir="$(config_get OUTPUT_DIR)"
    rsa_bits="$(config_get RSA_BITS "3072")"
    valid_days="$(config_get VALID_DAYS "365")"
    ca_cert="$(config_get CA_CERT)"
    ca_key="$(config_get CA_KEY)"
    server_cn="$(config_get SERVER_CN "kafka-server")"
    key_pass="$(config_get KEY_PASSWORD)"

    local server_key server_csr server_crt san_conf
    server_key="${output_dir}/server.key"
    server_csr="${output_dir}/server.csr"
    server_crt="${output_dir}/server.crt"
    san_conf="${TEMP_DIR}/server_san.cnf"

    generate_san_config "${san_conf}" true

    openssl genrsa -out "${server_key}" "${rsa_bits}" || \
        log_fatal "Failed to generate server private key"
    chmod 600 "${server_key}"

    local subject
    subject="$(build_subject "${server_cn}")"
    openssl req -new -key "${server_key}" -out "${server_csr}" \
        -subj "${subject}" -config "${san_conf}" || \
        log_fatal "Failed to generate server CSR"

    openssl x509 -req -in "${server_csr}" -CA "${ca_cert}" -CAkey "${ca_key}" \
        -CAcreateserial -out "${server_crt}" -days "${valid_days}" \
        -sha256 -extensions v3_req -extfile "${san_conf}" || \
        log_fatal "Failed to sign server certificate"

    chmod 644 "${server_crt}"
    chmod 600 "${server_csr}"

    log_success "Server certificate generated"
}

generate_client_cert() {
    log_info "Generating client certificate..."

    local output_dir rsa_bits valid_days ca_cert ca_key client_cn
    output_dir="$(config_get OUTPUT_DIR)"
    rsa_bits="$(config_get RSA_BITS "3072")"
    valid_days="$(config_get VALID_DAYS "365")"
    ca_cert="$(config_get CA_CERT)"
    ca_key="$(config_get CA_KEY)"
    client_cn="$(config_get CLIENT_CN "kafka-client")"

    local client_key client_csr client_crt san_conf
    client_key="${output_dir}/client.key"
    client_csr="${output_dir}/client.csr"
    client_crt="${output_dir}/client.crt"
    san_conf="${TEMP_DIR}/client_san.cnf"

    {
        printf "[req]\n"
        printf "distinguished_name = req_distinguished_name\n"
        printf "req_extensions = v3_req\n"
        printf "prompt = no\n"
        printf "[req_distinguished_name]\n"
        printf "[v3_req]\n"
        printf "keyUsage = keyEncipherment, dataEncipherment, digitalSignature\n"
        printf "extendedKeyUsage = clientAuth\n"
    } > "${san_conf}"

    openssl genrsa -out "${client_key}" "${rsa_bits}" || \
        log_fatal "Failed to generate client private key"
    chmod 600 "${client_key}"

    local subject
    subject="$(build_subject "${client_cn}")"
    openssl req -new -key "${client_key}" -out "${client_csr}" \
        -subj "${subject}" -config "${san_conf}" || \
        log_fatal "Failed to generate client CSR"

    openssl x509 -req -in "${client_csr}" -CA "${ca_cert}" -CAkey "${ca_key}" \
        -CAcreateserial -out "${client_crt}" -days "${valid_days}" \
        -sha256 -extensions v3_req -extfile "${san_conf}" || \
        log_fatal "Failed to sign client certificate"

    chmod 644 "${client_crt}"
    chmod 600 "${client_csr}"

    log_success "Client certificate generated"
}

# =============================================================================
# PKCS12 AND JKS GENERATION
# =============================================================================

generate_pkcs12() {
    log_info "Generating PKCS12 stores..."

    local output_dir keystore_pass key_pass server_cn client_cn
    output_dir="$(config_get OUTPUT_DIR)"
    keystore_pass="$(config_get KEYSTORE_PASSWORD)"
    key_pass="$(config_get KEY_PASSWORD)"
    server_cn="$(config_get SERVER_CN "kafka-server")"
    client_cn="$(config_get CLIENT_CN "kafka-client")"

    local server_key server_crt client_key client_crt ca_cert
    server_key="${output_dir}/server.key"
    server_crt="${output_dir}/server.crt"
    client_key="${output_dir}/client.key"
    client_crt="${output_dir}/client.crt"
    ca_cert="$(config_get CA_CERT)"

    local keystore_p12 client_p12
    keystore_p12="${output_dir}/kafka.keystore.p12"
    client_p12="${output_dir}/client.p12"

    openssl pkcs12 -export \
        -in "${server_crt}" \
        -inkey "${server_key}" \
        -certfile "${ca_cert}" \
        -name "${server_cn}" \
        -out "${keystore_p12}" \
        -password pass:"${keystore_pass}" || \
        log_fatal "Failed to generate server PKCS12 keystore"
    chmod 600 "${keystore_p12}"

    openssl pkcs12 -export \
        -in "${client_crt}" \
        -inkey "${client_key}" \
        -certfile "${ca_cert}" \
        -name "${client_cn}" \
        -out "${client_p12}" \
        -password pass:"${keystore_pass}" || \
        log_fatal "Failed to generate client PKCS12 keystore"
    chmod 600 "${client_p12}"

    log_success "PKCS12 stores generated"
}

generate_jks() {
    log_info "Generating JKS stores..."

    local output_dir keystore_pass truststore_pass server_cn client_cn
    output_dir="$(config_get OUTPUT_DIR)"
    keystore_pass="$(config_get KEYSTORE_PASSWORD)"
    truststore_pass="$(config_get TRUSTSTORE_PASSWORD)"
    server_cn="$(config_get SERVER_CN "kafka-server")"
    client_cn="$(config_get CLIENT_CN "kafka-client")"

    local keystore_p12 keystore_jks truststore_jks ca_cert
    keystore_p12="${output_dir}/kafka.keystore.p12"
    keystore_jks="${output_dir}/kafka.keystore.jks"
    truststore_jks="${output_dir}/kafka.truststore.jks"
    ca_cert="$(config_get CA_CERT)"

    keytool -importkeystore \
        -srckeystore "${keystore_p12}" \
        -srcstoretype PKCS12 \
        -srcstorepass "${keystore_pass}" \
        -destkeystore "${keystore_jks}" \
        -deststoretype JKS \
        -deststorepass "${keystore_pass}" \
        -noprompt || \
        log_fatal "Failed to convert PKCS12 to JKS keystore"
    chmod 600 "${keystore_jks}"

    keytool -import \
        -alias ca \
        -file "${ca_cert}" \
        -keystore "${truststore_jks}" \
        -storepass "${truststore_pass}" \
        -noprompt -trustcacerts || \
        log_fatal "Failed to create JKS truststore"
    chmod 600 "${truststore_jks}"

    log_success "JKS stores generated"
}

# =============================================================================
# CLIENT PROPERTIES
# =============================================================================

generate_client_properties() {
    log_info "Generating client.properties..."

    local output_dir client_props truststore_pass keystore_pass
    output_dir="$(config_get OUTPUT_DIR)"
    client_props="${output_dir}/client.properties"
    truststore_pass="$(config_get TRUSTSTORE_PASSWORD)"
    keystore_pass="$(config_get KEYSTORE_PASSWORD)"

    {
        printf "# Kafka Client Properties\n"
        printf "# Auto-generated by %s\n" "${SCRIPT_NAME}"
        printf "# Generated at: %s\n" "$(date -Iseconds)"
        printf "\n"
        printf "security.protocol=SSL\n"
        printf "ssl.truststore.location=%s/kafka.truststore.jks\n" "${output_dir}"
        printf "ssl.truststore.password=%s\n" "${truststore_pass}"
        printf "ssl.truststore.type=JKS\n"
        printf "ssl.keystore.location=%s/kafka.keystore.jks\n" "${output_dir}"
        printf "ssl.keystore.password=%s\n" "${keystore_pass}"
        printf "ssl.key.password=%s\n" "${keystore_pass}"
        printf "ssl.keystore.type=JKS\n"
        printf "ssl.endpoint.identification.algorithm=HTTPS\n"
    } > "${client_props}"

    chmod 600 "${client_props}"
    log_success "client.properties generated"
}

# =============================================================================
# MANIFEST GENERATION
# =============================================================================

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "${str}"
}

generate_manifest() {
    log_info "Generating manifest.json..."

    local output_dir manifest server_crt client_crt rsa_bits ca_cert
    output_dir="$(config_get OUTPUT_DIR)"
    manifest="${output_dir}/manifest.json"
    server_crt="${output_dir}/server.crt"
    client_crt="${output_dir}/client.crt"
    rsa_bits="$(config_get RSA_BITS "3072")"
    ca_cert="$(config_get CA_CERT)"

    # Extract certificate details using OpenSSL
    local server_not_after server_fingerprint server_sig_algo server_subject server_issuer
    server_not_after="$(openssl x509 -in "${server_crt}" -noout -enddate | cut -d= -f2)"
    server_fingerprint="$(openssl x509 -in "${server_crt}" -noout -fingerprint -sha256 | cut -d= -f2)"
    server_sig_algo="$(openssl x509 -in "${server_crt}" -noout -text | awk '/Signature Algorithm:/{print $3; exit}')"
    server_subject="$(openssl x509 -in "${server_crt}" -noout -subject | sed 's/subject=//')"
    server_issuer="$(openssl x509 -in "${server_crt}" -noout -issuer | sed 's/issuer=//')"

    local client_not_after client_fingerprint client_sig_algo client_subject client_issuer
    client_not_after="$(openssl x509 -in "${client_crt}" -noout -enddate | cut -d= -f2)"
    client_fingerprint="$(openssl x509 -in "${client_crt}" -noout -fingerprint -sha256 | cut -d= -f2)"
    client_sig_algo="$(openssl x509 -in "${client_crt}" -noout -text | awk '/Signature Algorithm:/{print $3; exit}')"
    client_subject="$(openssl x509 -in "${client_crt}" -noout -subject | sed 's/subject=//')"
    client_issuer="$(openssl x509 -in "${client_crt}" -noout -issuer | sed 's/issuer=//')"

    # Collect DNS SANs into a JSON array string
    local dns_sans=""
    local first=true
    local key
    for key in "${!CONFIG[@]}"; do
        if [[ "${key}" =~ ^SERVER_DNS_[0-9]+$ ]]; then
            if [[ "${first}" == "true" ]]; then
                first=false
            else
                dns_sans="${dns_sans}, "
            fi
            dns_sans="${dns_sans}\"$(json_escape "${CONFIG[${key}]}")\""
        fi
    done

    # Collect IP SANs into a JSON array string
    local ip_sans=""
    first=true
    for key in "${!CONFIG[@]}"; do
        if [[ "${key}" =~ ^SERVER_IP_[0-9]+$ ]]; then
            if [[ "${first}" == "true" ]]; then
                first=false
            else
                ip_sans="${ip_sans}, "
            fi
            ip_sans="${ip_sans}\"$(json_escape "${CONFIG[${key}]}")\""
        fi
    done

    # Build JSON manifest
    {
        printf "{\n"
        printf "  \"generated_at\": \"%s\",\n" "$(date -Iseconds)"
        printf "  \"script\": \"%s\",\n" "$(json_escape "${SCRIPT_NAME}")"
        printf "  \"rsa_bits\": %s,\n" "${rsa_bits}"
        printf "  \"server\": {\n"
        printf "    \"certificate\": \"server.crt\",\n"
        printf "    \"private_key\": \"server.key\",\n"
        printf "    \"csr\": \"server.csr\",\n"
        printf "    \"expiration\": \"%s\",\n" "$(json_escape "${server_not_after}")"
        printf "    \"sha256_fingerprint\": \"%s\",\n" "$(json_escape "${server_fingerprint}")"
        printf "    \"signature_algorithm\": \"%s\",\n" "$(json_escape "${server_sig_algo}")"
        printf "    \"subject\": \"%s\",\n" "$(json_escape "${server_subject}")"
        printf "    \"issuer\": \"%s\",\n" "$(json_escape "${server_issuer}")"
        printf "    \"dns_san\": [%s],\n" "${dns_sans}"
        printf "    \"ip_san\": [%s]\n" "${ip_sans}"
        printf "  },\n"
        printf "  \"client\": {\n"
        printf "    \"certificate\": \"client.crt\",\n"
        printf "    \"private_key\": \"client.key\",\n"
        printf "    \"csr\": \"client.csr\",\n"
        printf "    \"expiration\": \"%s\",\n" "$(json_escape "${client_not_after}")"
        printf "    \"sha256_fingerprint\": \"%s\",\n" "$(json_escape "${client_fingerprint}")"
        printf "    \"signature_algorithm\": \"%s\",\n" "$(json_escape "${client_sig_algo}")"
        printf "    \"subject\": \"%s\",\n" "$(json_escape "${client_subject}")"
        printf "    \"issuer\": \"%s\"\n" "$(json_escape "${client_issuer}")"
        printf "  },\n"
        printf "  \"keystores\": {\n"
        printf "    \"kafka_keystore_p12\": \"kafka.keystore.p12\",\n"
        printf "    \"kafka_keystore_jks\": \"kafka.keystore.jks\",\n"
        printf "    \"kafka_truststore_jks\": \"kafka.truststore.jks\",\n"
        printf "    \"client_p12\": \"client.p12\"\n"
        printf "  },\n"
        printf "  \"client_config\": \"client.properties\"\n"
        printf "}\n"
    } > "${manifest}"

    chmod 644 "${manifest}"
    log_success "manifest.json generated"
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_certificates() {
    log_info "Verifying certificates..."

    local output_dir ca_cert server_crt client_crt
    output_dir="$(config_get OUTPUT_DIR)"
    ca_cert="$(config_get CA_CERT)"
    server_crt="${output_dir}/server.crt"
    client_crt="${output_dir}/client.crt"

    if ! openssl verify -CAfile "${ca_cert}" "${server_crt}" >/dev/null 2>&1; then
        log_fatal "Server certificate verification failed against CA"
    fi
    log_success "Server certificate chain verified"

    if ! openssl verify -CAfile "${ca_cert}" "${client_crt}" >/dev/null 2>&1; then
        log_fatal "Client certificate verification failed against CA"
    fi
    log_success "Client certificate chain verified"

    log_success "Certificate verification passed"
}

verify_keystores() {
    log_info "Verifying keystores..."

    local output_dir keystore_pass truststore_pass
    output_dir="$(config_get OUTPUT_DIR)"
    keystore_pass="$(config_get KEYSTORE_PASSWORD)"
    truststore_pass="$(config_get TRUSTSTORE_PASSWORD)"

    local keystore_jks truststore_jks keystore_p12
    keystore_jks="${output_dir}/kafka.keystore.jks"
    truststore_jks="${output_dir}/kafka.truststore.jks"
    keystore_p12="${output_dir}/kafka.keystore.p12"

    if ! keytool -list -keystore "${keystore_jks}" -storepass "${keystore_pass}" -noprompt >/dev/null 2>&1; then
        log_fatal "JKS keystore validation failed"
    fi
    log_success "JKS keystore validated"

    if ! keytool -list -keystore "${truststore_jks}" -storepass "${truststore_pass}" -noprompt >/dev/null 2>&1; then
        log_fatal "JKS truststore validation failed"
    fi
    log_success "JKS truststore validated"

    if ! openssl pkcs12 -in "${keystore_p12}" -password pass:"${keystore_pass}" -noout >/dev/null 2>&1; then
        log_fatal "PKCS12 keystore validation failed"
    fi
    log_success "PKCS12 keystore validated"

    log_success "Keystore verification passed"
}

# =============================================================================
# IDEMPOTENCY CHECK
# =============================================================================

check_idempotency() {
    local output_dir force
    output_dir="$(config_get OUTPUT_DIR)"
    force="${FORCE:-false}"

    if [[ "${force}" == "true" ]]; then
        log_warning "Force mode enabled. Existing files will be overwritten."
        return 0
    fi

    local existing_files=()
    local files=(
        "server.key" "server.csr" "server.crt"
        "client.key" "client.csr" "client.crt"
        "kafka.keystore.p12" "kafka.keystore.jks"
        "kafka.truststore.jks" "client.p12"
        "client.properties" "manifest.json"
    )

    local f
    for f in "${files[@]}"; do
        if [[ -f "${output_dir}/${f}" ]]; then
            existing_files+=("${f}")
        fi
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
        log_warning "The following files already exist in ${output_dir}:"
        for f in "${existing_files[@]}"; do
            log_warning "  - ${f}"
        done
        log_fatal "Output files already exist. Set FORCE=true to overwrite, or remove them manually."
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "Starting Kafka certificate generation for Apache Kafka 4.x (KRaft)"
    log_info "Script: ${SCRIPT_NAME}"

    TEMP_DIR="$(mktemp -d -t kafka-certs.XXXXXXXXXX)"
    if [[ ! -d "${TEMP_DIR}" ]]; then
        log_fatal "Failed to create temporary directory"
    fi
    chmod 700 "${TEMP_DIR}"
    log_info "Temporary directory: ${TEMP_DIR}"

    validate_environment
    parse_config "${CONFIG_FILE}"
    validate_config
    check_idempotency

    generate_server_cert
    generate_client_cert
    generate_pkcs12
    generate_jks
    generate_client_properties
    generate_manifest

    verify_certificates
    verify_keystores

    local output_dir
    output_dir="$(config_get OUTPUT_DIR)"
    chmod 700 "${output_dir}"

    log_success "========================================"
    log_success "Certificate generation completed successfully!"
    log_success "Output directory: ${output_dir}"
    log_success "========================================"
}

main "$@"
