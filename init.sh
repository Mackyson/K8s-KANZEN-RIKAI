#!/bin/sh

mkdir bin

curl -LO "https://storage.googleapis.com/kubernetes-release/release/"(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"/bin/linux/amd64/kubectl"
# CAUTION!
# I use fish shell and its grammer isn't compatible with bash.
# If you're using bash, Please edit by yourself.

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.12.0/kind-linux-amd64

mv ./kind ./kubectl ./bin

export PATH=(pwd)"/bin:$PATH"
alias k=kubectl
