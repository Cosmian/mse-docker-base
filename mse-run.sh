#!/bin/bash

set -e

usage() {
    echo "mse-run usage: $0 --size <size> (--certificate <cert.pem> | --self-signed <expiration_timestamp> | --no-ssl) --code <tarball_path> --host <host> --application <module:application> --uuid <uuid> [--timeout <timeout_timestamp>] [--dry-run] "
    echo ""
    echo "Example (1): $0 --size 8G --code /tmp/app.tar --self-signed 1669155711 --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Example (2): $0 --size 8G --code /tmp/app.tar --certificate /tmp/cert.pem --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Example (3): $0 --size 8G --code /tmp/app.tar --no-ssl --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Arguments:"
    echo -e "\t--dry-run\tallow to compute MRENCLAVE value from a non-sgx machine"
    exit 1
}

timeout_die() {
    STATUS=$?
    if [ $STATUS -ge 124 ]; then
        exit 0
    else
        exit $STATUS
    fi
}

set_default_variables() {
    DEBUG=0
    ENCLAVE_SIZE=""
    EXPIRATION_DATE=""
    NO_SSL=0
    HOST=""
    CODE_TARBALL=""
    APPLICATION=""
    CERTIFICATE_PATH=""
    APP_DIR="/app"
    CODE_PATH="$APP_DIR/code"
    CERT_PATH="$APP_DIR/fullchain.pem"
    SGX_SIGNER_KEY="$HOME/.config/gramine/enclave-key.pem"
    DRY_RUN=0
    TIMEOUT_DATE=""
    UUID=""
}

parse_args() {
    echo "Reading args: $*"
    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --size)
            ENCLAVE_SIZE="$2"
            shift # past argument
            shift # past value
            ;;

            --certificate)
            CERTIFICATE_PATH="$2"
            shift # past argument
            shift # past value
            ;;

            --self-signed)
            EXPIRATION_DATE="$2"
            shift # past argument
            shift # past value
            ;;

            --no-ssl)
            NO_SSL=1
            shift # past argument
            ;;

            --code)
            CODE_TARBALL="$2"
            shift # past argument
            shift # past value
            ;;

            --host)
            HOST="$2"
            shift # past argument
            shift # past value
            ;;

            --application)
            APPLICATION="$2"
            shift # past argument
            shift # past value
            ;;

            --uuid)
            UUID="$2"
            shift # past argument
            shift # past value
            ;;

            --timeout)
            TIMEOUT_DATE="$2"
            shift # past argument
            shift # past value
            ;;

            --dry-run)
            DRY_RUN=1
            shift # past argument
            ;;

            --debug)
            DEBUG=1
            shift # past argument
            ;;

            -*)
            usage
            ;;
        esac
    done

    if [ -z "$ENCLAVE_SIZE" ] || [ -z "$CODE_TARBALL" ] || [ -z "$HOST" ] || [ -z "$APPLICATION" ] || [ -z "$UUID" ]
    then
        usage
    fi

    if [ -z "$CERTIFICATE_PATH" ] && [ -z "$EXPIRATION_DATE" ] && [ $NO_SSL -eq 0 ]
    then
        usage
    fi
}

set_default_variables
parse_args "$@"

# Don't write .pyc files
export PYTHONDONTWRITEBYTECODE=1
# Other directory for __pycache__ folders
export PYTHONPYCACHEPREFIX=/tmp

echo "Untar the code..."
mkdir -p "$CODE_PATH"
tar xvf "$CODE_TARBALL" -C "$CODE_PATH"

# Install dependencies
# /!\ should not be used to verify MRENCLAVE on client side
# even if you freeze all your dependencies in a requirements.txt file
# there are side effects and hash digest of some files installed may differ
if [ -e "$CODE_PATH/requirements.txt" ]; then
    echo "Installing deps..."
    pip install -r $CODE_PATH/requirements.txt
fi

# Prepare the certificate if necessary
if [ -n "$CERTIFICATE_PATH" ]; then
    cp "$CERTIFICATE_PATH" "$CERT_PATH"
fi

if [ $NO_SSL -eq 1 ]; then
    SSL_APP_MODE="--no-ssl"
    SSL_APP_MODE_VALUE=""
elif [ -z "$CERTIFICATE_PATH" ]; then
    SSL_APP_MODE="--self-signed"
    SSL_APP_MODE_VALUE="$EXPIRATION_DATE"
else
    SSL_APP_MODE="--certificate"
    SSL_APP_MODE_VALUE="$CERT_PATH"
fi

# Prepare gramine argv
# /!\ no double quote around $SSL_APP_MODE_VALUE which might be empty
# otherwise it will be serialized by gramine
gramine-argv-serializer "python3" "/usr/local/bin/mse-bootstrap" \
    "$SSL_APP_MODE" $SSL_APP_MODE_VALUE \
    "--host" "$HOST" \
    "--port" "443" \
    "--app-dir" "$CODE_PATH" \
    "--uuid" "$UUID" \
    "$APPLICATION" > args

echo "Generating the enclave..."

if [ $DRY_RUN -eq 0 ]; then
    if ! [ -e "/dev/sgx_enclave" ]; then
        echo "You are not running on an sgx machine"
        echo "If you want to compute the MR_ENCLAVE, re-run with --dry-run parameter"
        exit 1
    fi

    # Build the gramine program
    make clean && make SGX=1 DEBUG="$DEBUG" ENCLAVE_SIZE="$ENCLAVE_SIZE" APP_DIR="$APP_DIR" SGX_SIGNER_KEY="$SGX_SIGNER_KEY"

    # Start the enclave
    if [ -z "$TIMEOUT_DATE" ]; then
        # Forever
        gramine-sgx ./python
    else
        NOW=$(date +"%s")
        DURATION=$(( TIMEOUT_DATE-NOW ))
        echo "Starting gramine-sgx for $DURATION seconds"
        timeout -k 10 "$DURATION" gramine-sgx ./python || timeout_die
    fi
else
    # Generate a dummy key if you just want to get MRENCLAVE
    gramine-sgx-gen-private-key
    # Compile for the output including MRENCLAVE
    make clean && make SGX=1 DEBUG="$DEBUG" ENCLAVE_SIZE="$ENCLAVE_SIZE" APP_DIR="$APP_DIR" SGX_SIGNER_KEY="$SGX_SIGNER_KEY"
fi
