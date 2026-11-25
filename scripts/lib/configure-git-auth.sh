# Configure git for private Lightwell source clones.
# Source from factory scripts; do not execute directly.
# Reads GIT_AUTH_PATH (optional Tekton git-auth workspace).

configure_git_for_private_source() {
    # Corporate CAs (gitlab.cee.redhat.com) — same pattern as python source-to-sdist.
    # Task mounts trusted-ca at /mnt/trusted-ca when present.
    local ca
    for ca in /mnt/trusted-ca/ca-bundle.crt /etc/pki/tls/certs/ca-custom-bundle.crt; do
        if [[ -s "${ca}" ]]; then
            export GIT_SSL_CAINFO="${ca}"
            export SSL_CERT_FILE="${ca}"
            echo "[configure-git-auth] using CA bundle ${ca}"
            break
        fi
    done

    # Optional git-auth workspace for private Lightwell mirror clones.
    # Use GIT_CONFIG_GLOBAL + an explicit store file so we do not override HOME.
    if [[ -z "${GIT_AUTH_PATH:-}" || ! -d "${GIT_AUTH_PATH}" ]]; then
        return 0
    fi

    local git_config_dir creds_file
    git_config_dir="$(mktemp -d)"
    chmod 700 "${git_config_dir}"
    export GIT_CONFIG_GLOBAL="${git_config_dir}/.gitconfig"
    creds_file="${git_config_dir}/.git-credentials"

    if [[ -f "${GIT_AUTH_PATH}/.gitconfig" ]]; then
        cp -f "${GIT_AUTH_PATH}/.gitconfig" "${GIT_CONFIG_GLOBAL}"
    fi
    # Pin store to our temp file (overrides any helper from a copied .gitconfig).
    git config --global credential.helper "store --file=${creds_file}"

    if [[ -f "${GIT_AUTH_PATH}/.git-credentials" ]]; then
        cp -f "${GIT_AUTH_PATH}/.git-credentials" "${creds_file}"
        echo "[configure-git-auth] configured git credentials from git-auth workspace"
        return 0
    fi

    # username/password secret → git credential store (git encodes the file itself).
    if [[ -f "${GIT_AUTH_PATH}/username" && -f "${GIT_AUTH_PATH}/password" ]]; then
        local user pass
        user="$(tr -d '\n' <"${GIT_AUTH_PATH}/username")"
        pass="$(tr -d '\n' <"${GIT_AUTH_PATH}/password")"
        printf 'protocol=https\nhost=gitlab.cee.redhat.com\nusername=%s\npassword=%s\n\n' \
            "${user}" "${pass}" | git credential approve
        echo "[configure-git-auth] configured git credentials from username/password"
    fi
}
