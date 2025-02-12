#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2021
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

service_name="helloworld-go"

if ! command -v kn; then
    echo "This funtional test requires Knative client"
    exit 1
fi

# Setup
kn service create "$service_name" --image gcr.io/knative-samples/helloworld-go --env TARGET="Go Sample v1"

# Test
info "===== Test started ====="
assert_non_empty "$(kn service describe "$service_name")" "Knative client could't create a $service_name app"
assert_contains "$(kn service describe "$service_name")" "++ Ready" "$service_name app is no ready"
assert_contains "$(kn service describe "$service_name")" "++ ConfigurationsReady" "$service_name app's configuration is no ready"
assert_contains "$(kn service describe "$service_name")" "++ RoutesReady" "$service_name app's routes is no ready"

info "===== Test completed ====="

# Teardown
kn service delete "$service_name"
