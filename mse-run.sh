#!/bin/bash

set -e

usage() {
    echo "mse-run usage: $0 --size <size> (--certificate <cert.pem> | --ratls <expiration_timestamp> | --no-ssl) --code <tarball_path> --host <host> --application <module:application> --uuid <uuid> [--timeout <timeout_timestamp>] [--dry-run] [--memory] "
    echo ""
    echo "Example (1): $0 --size 8G --code /tmp/app.tar --ratls 1669155711 --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Example (2): $0 --size 8G --code /tmp/app.tar --certificate /tmp/cert.pem --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Example (3): $0 --size 8G --code /tmp/app.tar --no-ssl --host localhost --application app:app --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15"
    echo ""
    echo "Arguments:"
    echo -e "\t--debug      put the enclave in debug mode"
    echo -e "\t--dry-run    allow to compute MRENCLAVE value from a non-sgx machine"
    echo -e "\t--force      regenerate and recompile files if they are already existed from another enclave"
    echo -e "\t--memory     print the memory usage"
    echo -e "\t--timeout    stop the enclave after this delay"

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
    HOST="0.0.0.0"
    PORT="443"
    CODE_TARBALL=""
    APPLICATION=""
    CERTIFICATE_PATH=""
    APP_DIR="/tmp/app"
    CERT_PATH="$APP_DIR/fullchain.pem"
    SGX_SIGNER_KEY="$HOME/.config/gramine/enclave-key.pem"
    CODE_DIR="code"
    HOME_DIR="home"
    KEY_DIR="key"
    DRY_RUN=0
    MEMORY=0
    FORCE=0
    TIMEOUT=""
    ID=""
    SUBJECT="CN=cosmian.app,O=Cosmian Tech,C=FR,L=Paris,ST=Ile-de-France"
    SUBJECT_ALTERNATIVE_NAME="localhost"
    MANIFEST_SGX="python.manifest.sgx"
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

            --ratls)
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

            --port)
            PORT="$2"
            shift # past argument
            shift # past value
            ;;

            --application)
            APPLICATION="$2"
            shift # past argument
            shift # past value
            ;;

            --id)
            ID="$2"
            shift # past argument
            shift # past value
            ;;

            --subject)
            SUBJECT="$2"
            shift # past argument
            shift # past value
            ;;

            --san)
            SUBJECT_ALTERNATIVE_NAME="$2"
            shift # past argument
            shift # past value
            ;;

            --timeout)
            TIMEOUT="$2"
            shift # past argument
            shift # past value
            ;;

            --dry-run)
            DRY_RUN=1
            shift # past argument
            ;;

            --memory)
            MEMORY=1
            shift # past argument
            ;;

            --debug)
            DEBUG=1
            shift # past argument
            ;;

            --force)
            FORCE=1
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

# If the manifest exist, ignore all the installation and compilation steps
# Do it anyways if --force
if [ ! -f $MANIFEST_SGX ] || [ $FORCE -eq 1 ]; then
    echo "Untar the code..."
    mkdir -p "$APP_DIR"
    tar xvf "$CODE_TARBALL" -C "$APP_DIR"

    # Install dependencies
    # /!\ should not be used to verify MRENCLAVE on client side
    # even if you freeze all your dependencies in a requirements.txt file
    # there are side effects and hash digest of some files installed may differ
    if [ -e "$APP_DIR/requirements.txt" ]; then
        echo "Installing deps..."
        if [ -n "$GRAMINE_VENV" ]; then
            # shellcheck source=/dev/null
            . "$GRAMINE_VENV/bin/activate"
        fi
        pip install -r $APP_DIR/requirements.txt
        if [ -n "$GRAMINE_VENV" ]; then
            deactivate
        fi
    fi

    # Prepare the certificate if necessary
    if [ -n "$CERTIFICATE_PATH" ]; then
        cp "$CERTIFICATE_PATH" "$CERT_PATH"
    fi

    # Remove previous generated files if exists
    if [ $FORCE -eq 1 ]; then
        rm -rf $CODE_DIR $HOME_DIR $KEY_DIR
    fi

    if [ $NO_SSL -eq 1 ]; then
        SSL_APP_MODE="--no-ssl"
        SSL_APP_MODE_VALUE=""
    elif [ -z "$CERTIFICATE_PATH" ]; then
        SSL_APP_MODE="--ratls"
        SSL_APP_MODE_VALUE="$EXPIRATION_DATE"
    else
        SSL_APP_MODE="--certificate"
        SSL_APP_MODE_VALUE="$CERT_PATH"
    fi

    # Prepare gramine argv
    # /!\ no double quote around $SSL_APP_MODE_VALUE which might be empty
    # otherwise it will be serialized by gramine
    gramine-argv-serializer "/usr/bin/python3" "-S" "/usr/local/bin/mse-bootstrap" \
        "$SSL_APP_MODE" $SSL_APP_MODE_VALUE \
        "--host" "$HOST" \
        "--port" "$PORT" \
        "--app-dir" "$APP_DIR" \
        "--subject" "$SUBJECT" \
        "--san" "$SUBJECT_ALTERNATIVE_NAME" \
        "--id" "$ID" \
        "--timeout" "$TIMEOUT" \
        "$APPLICATION" > args

    echo "Generating the enclave..."

    if [ $DRY_RUN -eq 1 ]; then
        # Generate a dummy key if you just want to get MRENCLAVE
        gramine-sgx-gen-private-key
    fi

    VENV=""
    if [ -n "$GRAMINE_VENV" ]; then
        VENV="GRAMINE_VENV=$GRAMINE_VENV"
    fi

    # Build the gramine program
    make clean && make SGX=1 $VENV \
                    DEBUG="$DEBUG" \
                    ENCLAVE_SIZE="$ENCLAVE_SIZE" \
                    APP_DIR="$APP_DIR" \
                    SGX_SIGNER_KEY="$SGX_SIGNER_KEY" \
                    CODE_DIR="$CODE_DIR" \
                    HOME_DIR="$HOME_DIR" \
                    KEY_DIR="$KEY_DIR"
fi

if [ $MEMORY -eq 1 ]; then
    mse-memory python.manifest.sgx
fi

if [ $DRY_RUN -eq 0 ]; then
    if ! [ -e "/dev/sgx_enclave" ]; then
        echo "You are not running on an sgx machine"
        echo "If you want to compute the MR_ENCLAVE, re-run with --dry-run parameter"
        exit 1
    fi

    # Start the enclave
    gramine-sgx ./python
fi
