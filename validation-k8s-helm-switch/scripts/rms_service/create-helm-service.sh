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
  name: rms_1
  identifier: rms_1
  description: ""
  gitOpsEnabled: false
  serviceDefinition:
    type: NativeHelm
    spec:
      variables:
        - name: on_call_handler
          type: String
          value: oncall-cms-engg
          required: false
        - name: VaultPath
          type: String
          value: secret/non-prod/cms/rms/dev-apse1
          required: false
        - name: prometheus_metrics_name
          type: String
          value: http_server_requests_latency_seconds
          required: false
        - name: prometheus_4xx_query
          type: String
          value: sum(rate(http_server_requests_seconds_count{status =~"4.*",pod="\$hostName"})) by (le)
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
        - name: APP_IAM_ROLE
          type: String
          value: arn:aws:iam::247502221416:role/cms-rms-pp-role-irsa
          valueType: TEXT
        - name: ManifestFilePath
          type: String
          value: hs-k8s-app-inventory/cms/rms/manifest.yaml
          required: false
        - name: RepoName
          type: String
          value: cms-rms
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
          value: CMS
          required: false
        - name: AdditionalParameters
          type: String
          value: "--hpaUpdate=false --applyAlertmanager=false"
          required: false
        - name: AppName
          type: String
          value: rms
          required: false
        - name: CanaryPercentage
          type: String
          value: "1"
          required: false
        - name: EnableExcessiveResourcePruning
          type: String
          value: "True"
          required: false
        - name: EnableControlledCanary
          type: String
          required: false
          description: ""
          value: "True"
      artifacts:
        primary:
          primaryArtifactRef: <+input>
          sources:
            - identifier: rms
              type: Ecr
              spec:
                connectorRef: account.amazon_web_services
                region: us-east-1
                imagePath: rms
                tag: <+input>
      manifests:
        - manifest:
            identifier: rms_1_helmChart
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
  --arg id      "rms_1" \
  --arg name    "rms_1" \
  --argjson yml "$YAML_JSON" \
  '{orgIdentifier: $org, projectIdentifier: $project, identifier: $id, name: $name, yaml: $yml}')

URL="${HARNESS_BASE_URL}/ng/api/servicesV2?accountIdentifier=${HARNESS_ACCOUNT_ID}"

echo "Creating service 'rms_1' (NativeHelm) ..."
RESP=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
  -H "x-api-key: ${HARNESS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESP" | tail -n1)
CONTENT=$(echo "$RESP" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Service 'rms_1' created."
  echo "$CONTENT" | jq .
else
  echo "FAILED (HTTP ${HTTP_CODE}):"
  echo "$CONTENT" | jq . 2>/dev/null || echo "$CONTENT"
  exit 1
fi
