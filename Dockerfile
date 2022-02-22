FROM golang:1.16

ARG ssh_key

RUN mkdir -p ~/.ssh -m 700 \
    && echo "StrictHostKeyChecking no " > /root/.ssh/config \
    && echo $ssh_key | base64 --decode > ~/.ssh/id_ed25519 \
    && chmod 600 /root/.ssh/id_ed25519 \
    && echo "[url \"git@github.com:\"]\n\tinsteadOf = https://github.com/" >> /root/.gitconfig

RUN mkdir -p /go/src/github.com/ghostmonitor/go-shopify
WORKDIR /go/src/github.com/ghostmonitor/go-shopify
ADD . ./
