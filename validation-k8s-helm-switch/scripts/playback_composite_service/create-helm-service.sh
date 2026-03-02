set -euo pipefail

# ── Config (override via env / .env) ──
HARNESS_BASE_URL="${HARNESS_BASE_URL:-https://app.harness.io}"
HARNESS_ACCOUNT_ID="${HARNESS_ACCOUNT_ID:?Set HARNESS_ACCOUNT_ID}"
HARNESS_API_KEY="${HARNESS_API_KEY:?Set HARNESS_API_KEY}"
HARNESS_ORG_ID="${HARNESS_ORG_ID:-default}"
HARNESS_PROJECT_ID="${HARNESS_PROJECT_ID:?Set HARNESS_PROJECT_ID}"

HELM_CONNECTOR_REF="${HELM_CONNECTOR_REF:?Set HELM_CONNECTOR_REF}"
HELM_CHART_PATH="${HELM_CHART_PATH:?Set HELM_CHART_PATH}"
HELM_REPO_BRANCH="${HELM_REPO_BRANCH:-main}"
HELM_VERSION="${HELM_VERSION:-V3}"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

SERVICE_YAML=$(cat <<YAML
service:
  name: playback-composite-1
  identifier: playback_composite_1
  description: ""
  gitOpsEnabled: false
  serviceDefinition:
    type: NativeHelm
    spec:
      variables:
        - name: TestConfigFilePath
          type: String
          value: harness-ng-projects/Org/hotstar/Projects/Playback/Test Configs/playback-composite.yaml
          required: false
        - name: OTEL_SERVICE_NAME
          type: String
          value: playback-composite
          required: false
        - name: OTEL_TRACING_ENABLED
          type: String
          value: "false"
          required: false
        - name: OTEL_INSTRUMENTATION_TYPE
          type: String
          value: go_manual
          required: false
        - name: ManifestFilePath
          type: String
          value: hs-k8s-app-inventory/platform/pcdds/manifest.yaml
          required: false
        - name: on_call_handler
          type: String
          value: oncall-playback-engg
          required: false
        - name: prometheus_metrics_name
          type: String
          value: http_server_requests_latency_seconds
          required: false
        - name: prometheus_4xx_query
          type: String
          value: sum(increase(play_resp_err_code_count{ err_code=~"ERR_PB_.*", pod="\$hostName"}[1m])) by (le)
          required: false
        - name: prometheus_5xx_query
          type: String
          value: sum(rate(http_server_requests_seconds_count{status =~"5.*",pod="\$hostName"})) by (le)
          required: false
        - name: prometheus_p90_query
          type: String
          value: histogram_quantile(0.90, sum(rate(http_server_requests_seconds{pod="\$hostName"})) by (le))
          required: false
        - name: prometheus_p50_query
          type: String
          value: histogram_quantile(0.50, sum(rate(http_server_requests_seconds{pod="\$hostName"})) by (le))
          required: false
        - name: SkipTerraformExport
          type: String
          value: "False"
          required: false
        - name: RepoName
          type: String
          value: playback-composite
          required: false
        - name: TerraformRootDir
          type: String
          value: terraform
          required: false
        - name: SkipTerraform
          type: String
          value: "False"
          required: false
        - name: Jira_Component
          type: String
          value: composite
          required: false
        - name: AdditionalParameters
          type: String
          value: "--hpaUpdate=false --applyAlertmanager=false"
          required: false
        - name: AppName
          type: String
          value: playback-composite
          required: false
        - name: CanaryPercentage
          type: String
          value: "1"
          required: false
        - name: SchemaFilePath
          type: String
          value: playback/graph
          required: false
        - name: EndgameE2EFailure
          type: String
          value: "False"
          required: false
        - name: EndgameE2ETags
          type: String
          value: "null"
          required: false
        - name: EndgameTestsBranch
          type: String
          value: development
          required: false
        - name: EndgamePropFilePath
          type: String
          value: configs/dev/in-test.properties
          required: false
        - name: EndgameEndpoint
          type: String
          value: https://origin-endgame.preprod.hotstar-labs.com
          required: false
        - name: EndgameSlackHandles
          type: String
          value: <@oncall-playback-engg>
          required: false
        - name: EndgameTags
          type: String
          value: "null"
          required: false
        - name: DisablePagerEndgame
          type: String
          value: "True"
          required: false
        - name: EndgameThread
          type: String
          value: "1"
          required: false
        - name: IncrementalCanaryApprovals
          type: String
          value: "True"
          required: false
        - name: EnableControlledCanary
          type: String
          description: ""
          required: false
          value: "True"
        - name: EnableExcessiveResourcePruning
          type: String
          value: "True"
          required: false
        - name: CanaryScaleDownWaitDuration
          type: String
          description: ""
          required: false
          value: 60s
      artifacts:
        primary:
          primaryArtifactRef: playback_composite_in
          sources:
            - identifier: playback_composite_in
              type: Ecr
              spec:
                connectorRef: account.amazon_web_services
                region: us-east-1
                imagePath: playback-composite-in
                tag: <+input>
      manifests:
        - manifest:
            identifier: playback_composite_1_helmChart
            type: HelmChart
            spec:
              store:
                type: Git
                spec:
                  connectorRef: ${HELM_CONNECTOR_REF}
                  gitFetchType: Branch
                  folderPath: ${HELM_CHART_PATH}
                  branch: ${HELM_REPO_BRANCH}
              helmVersion: ${HELM_VERSION}
              skipResourceVersioning: false
YAML
)

# ── Dry run: just print the YAML ──
if [[ "$DRY_RUN" == true ]]; then
  echo "$SERVICE_YAML"
  exit 0
fi

# ── Create service via API ──
YAML_JSON=$(printf '%s' "$SERVICE_YAML" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

BODY=$(jq -n \
  --arg org     "$HARNESS_ORG_ID" \
  --arg project "$HARNESS_PROJECT_ID" \
  --arg id      "playback_composite_1" \
  --arg name    "playback-composite-1" \
  --argjson yml "$YAML_JSON" \
  '{orgIdentifier: $org, projectIdentifier: $project, identifier: $id, name: $name, yaml: $yml}')

URL="${HARNESS_BASE_URL}/ng/api/servicesV2?accountIdentifier=${HARNESS_ACCOUNT_ID}"

echo "Creating service 'playback_composite_1' (NativeHelm) ..."
RESP=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
  -H "x-api-key: ${HARNESS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESP" | tail -n1)
CONTENT=$(echo "$RESP" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Service 'playback_composite_1' created."
  echo "$CONTENT" | jq .
else
  echo "FAILED (HTTP ${HTTP_CODE}):"
  echo "$CONTENT" | jq . 2>/dev/null || echo "$CONTENT"
  exit 1
fi
