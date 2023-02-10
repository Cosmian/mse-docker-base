# MicroService Encryption Docker Base

## Overview

Base docker image used for Python web application launched with [MSE](https://cosmian.com/microservice-encryption/).

The docker image is built and released with GitHub Actions as below:

```console
$ export BUILD_DATE="$(date "+%Y%m%d%H%M%S")"
$ docker build -t mse-base:$BUILD_DATE .
```

You should use images released on [pkgs/mse-base](https://github.com/Cosmian/mse-docker-base/pkgs/container/mse-base) as base layer.

## Extend with your own dependencies

As an example, `mse-base` can be extended with [Flask](https://flask.palletsprojects.com/en/2.2.x/):

```
FROM ghcr.io/cosmian/mse-base:LAST_DATE_ON_GH_PACKAGES

RUN pip3 install "flask==2.2.2"
```

replace `LAST_DATE_ON_GH_PACKAGES` with the last one on [pkgs/mse-base](https://github.com/Cosmian/mse-docker-base/pkgs/container/mse-base), then:

```console
$ docker build -t mse-flask:2.2.2
```

## Run with SGX

First compress your Python flask application:

```console
$ tree mse_src/
mse_src
└── app.py

0 directories, 2 files
$ cat mse_src/app.py
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello World!"
$ tar -cvf /tmp/app.tar --directory=mse_src app.py
```

then generate a signer RSA key for the enclave:

```console
$ openssl genrsa -3 -out enclave-key.pem 3072
```

and finally run the docker container with:

- Enclave signer key mounted to `/root/.config/gramine/enclave-key.pem`
- Tar of the python application mounted anywhere (`/tmp/app.tar` can be used)
- `mse-run` binary as docker entrypoint
- Enclave size in `--size` (could be `2G`, `4G`, `8G`)
- Path of the tar mounted previously in `--code`
- Module path of your Flask application in `--application` (usually `app:app`)
- Random UUID v4 in `--uuid`
- Expiration date of the certificate as unix epoch time in `--self-signed`

```console
$ docker run -p 8080:443 \
    --device /dev/sgx_enclave \
    --device /dev/sgx_provision \
    --device /dev/sgx/enclave \
    --device /dev/sgx/provision \
    -v /var/run/aesmd:/var/run/aesmd \
    -v "$(realpath enclave-key.pem)":/root/.config/gramine/enclave-key.pem \
    -v /tmp/app.tar:/tmp/app.tar \
    --entrypoint mse-run \
    mse-flask:2.2.2 --size 8G \
                    --code /tmp/app.tar \
                    --host localhost \
                    --application app:app \
                    --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15 \
                    --self-signed 1769155711
```

## Check microservice status

```console
$ # get self-signed certificate with OpenSSL
$ openssl s_client -showcerts -connect localhost:8080 </dev/null 2>/dev/null | openssl x509 -outform PEM >/tmp/cert.pem
$ # force self-signed certificate as CA bundle
$ curl https://localhost:8080 --cacert /tmp/cert.pem
```

## Compute MRENCLAVE without SGX

The integrity of the application running in `mse-flask` is reflected in the `MRENCLAVE` value which is a SHA-256 hash digest of code, data, heap, stack, and other attributes of an enclave.

Use `--dry-run` parameter with the exact same other parameters as above to output `MRENCLAVE` value:

```console
$ docker run --rm \
    -v /tmp/app.tar:/tmp/app.tar \
    --entrypoint mse-run \
    mse-flask:2.2.2 --size 8G \
                    --code /tmp/app.tar \
                    --host localhost \
                    --application app:app \
                    --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15 \
                    --self-signed 1769155711 \
                    --dry-run
```

__Note__: `MRSIGNER` value should be ignored because it is randomly generated at each dry run.


## Testing docker environment

If you want to test that your docker image contains all the dependencies needed, `mse-test` wraps `flask run` command for you if you mount your code directory to `/mse-app`:

```console
$ docker run --rm -ti \
    --entrypoint mse-test \
    --net host \
    -v mse_src:/mse-app \
    mse-flask:2.2.2 \
    --application app:app \
    --debug
$ # default host and port of flask developement server
$ curl http://127.0.0.1:5000
```

To use your `secrets.json`, just add `-v secrets.json:/root/.cache/mse/secrets.json` to mount the file.


## Determine the enclave memory size of your image

Some files contained in the docker are mounted into the enclave: libs, etc. 
These files takes some memory spaces from the enclave size you have declared. The remaining space is the effective memory your app can use.

You can compute the effective memory by adding `--memory` in the previous commands. For example:

```console
$ docker run --rm \
    -v /tmp/app.tar:/tmp/app.tar \
    --entrypoint mse-run \
    mse-flask:2.2.2 --size 8G \
                    --code /tmp/app.tar \
                    --host localhost \
                    --application app:app \
                    --uuid 533a2b83-4bc5-4a9c-955e-208c530bfd15 \
                    --self-signed 1769155711 \
                    --dry-run
                    --memory
```