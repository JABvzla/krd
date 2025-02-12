#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2018
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=tests/_functions.sh
source _functions.sh

server_deployment_name="server"

function cleanup {
    destroy_deployment "$server_deployment_name"
    kubectl delete pod client --ignore-not-found --now
    kubectl delete service server --ignore-not-found
    kubectl label namespace default istio-injection-
    kubectl delete peerauthentications default --ignore-not-found
}

function create_client {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: client
spec:
  containers:
    - image: gcr.io/google-samples/istio/loadgen:v0.0.1
      name: main
      env:
        - name: SERVER_ADDR
          value: http://server:80/
        - name: REQUESTS_PER_SECOND
          value: '10'
EOF
    kubectl wait --for=condition=ready pods client --timeout=3m
}

trap cleanup EXIT

# Setup
kubectl label namespace default istio-injection=enabled --overwrite
kubectl get namespaces --show-labels

# Test
info "===== Test started ====="

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $server_deployment_name
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: server
  template:
    metadata:
      labels:
        app.kubernetes.io/name: server
    spec:
      containers:
      - image: gcr.io/google-samples/istio/helloserver:v0.0.1
        name: main
---
apiVersion: v1
kind: Service
metadata:
  name: server
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app.kubernetes.io/name: server
  type: LoadBalancer
EOF
wait_deployment "$server_deployment_name"
create_client

assert_contains "$(kubectl get pods -l=app.kubernetes.io/name=server -o jsonpath='{range .items[0].spec.containers[*]}{.image}{"\n"}{end}')" "istio/proxy" "Istio proxy wasn't injected into the server's pod"

assert_non_empty "$(kubectl logs client)" "There is no client's logs"
assert_contains "$(kubectl logs client)" "Starting loadgen" "The client's pod doesn't start it"
assert_contains "$(kubectl logs client)" "10 request(s) complete to http://server:80/" "The client's pod can't connect to the server"

kubectl delete pod client --ignore-not-found --now

cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT
EOF
create_client
assert_non_empty "$(kubectl logs client)" "There is no client's logs"
assert_contains "$(kubectl logs client)" "Starting loadgen" "The client's pod doesn't start it"
assert_contains "$(kubectl logs client)" "10 request(s) complete to http://server:80/" "The client's pod can't connect to the server"

info "===== Test completed ====="
