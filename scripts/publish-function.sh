#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

if [ $# -lt 6 ]; then
  echo "Usage: $0 <botDirectory> <projectId> <bucket> <keyLocation> <keyRing> <functionRegion> [functionRuntime] [timeout]"
  exit 1
fi

directoryName=$1
project=$2
bucket=$3
keyLocation=$4
keyRing=$5
functionRegion=$6
# Optional parameter. If not specified, this flag won't be set when
# deploying the bot.
timeout=$8

# To use a different runtime for a bot, give 7th parameter in bot's
# cloudbuild.yaml.
if [ $# -ge 7 ]; then
    functionRuntime=$7
else
    functionRuntime=nodejs10
fi

botName=$(echo "${directoryName}" | rev | cut -d/ -f1 | rev)
workdir=$(pwd)
targetDir="${workdir}/targets/${botName}"

pushd "${targetDir}"
functionName=${botName//-/_}
queueName=${botName//_/-}

echo "About to publish function ${functionName}"
gcloud functions deploy "${functionName}" \
  --trigger-http \
  --runtime "${functionRuntime}" \
  --region "${functionRegion}" \
  --update-env-vars DRIFT_PRO_BUCKET="${bucket}",KEY_LOCATION="${keyLocation}",KEY_RING="${keyRing}",GCF_SHORT_FUNCTION_NAME="${functionName}",PROJECT_ID="${project}",GCF_LOCATION="${functionRegion}",PUPPETEER_SKIP_CHROMIUM_DOWNLOAD='1',WEBHOOK_TMP=tmp-webhook-payloads \
  ${timeout:+--timeout "${timeout}"}

echo "Adding ability for allUsers to execute the Function"
gcloud alpha functions add-iam-policy-binding "${functionName}" \
  --region="${functionRegion}" \
  --member=allUsers \
  --role=roles/cloudfunctions.invoker

echo "Deploying Queue ${queueName}"

verb="create"
if gcloud tasks queues describe "${queueName}"  &>/dev/null; then
  verb="update"
fi

gcloud tasks queues ${verb} "${queueName}" \
  --max-concurrent-dispatches="2048" \
  --max-attempts="100" \
  --max-retry-duration="43200s" \
  --max-dispatches-per-second="500" \
  --min-backoff="5s"
