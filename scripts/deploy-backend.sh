#!/bin/sh
# Deploy only to the shared Steady Demo project. No credentials belong in this file.
set -eu
cd "$(dirname "$0")/.."

mode="${1:-plan}"
case "$mode" in
  plan|apply) ;;
  *) echo 'Usage: sh scripts/deploy-backend.sh [plan|apply]' >&2; exit 2 ;;
esac

project_ref=sipqoeqvwkaljqifddxd
if [ "${SUPABASE_PROJECT_ID:-$project_ref}" != "$project_ref" ]; then
  echo 'Refusing to deploy: SUPABASE_PROJECT_ID is not the Steady Demo project.' >&2
  exit 1
fi
: "${SUPABASE_ACCESS_TOKEN:?Set your own Supabase access token in the environment.}"
# The CLI obtains a temporary database login using the scoped access token.
# A master database password is neither required nor stored in GitHub.
unset SUPABASE_DB_PASSWORD
python3 scripts/check_backend.py

# Stay on the tested v2 CLI; v3 changes remote targeting and confirmation flags.
# Explicit project targeting avoids a stale machine-local link. Never include seeds.
echo "Checking pending migrations for Steady Demo ($project_ref)..."
npx --yes supabase@2.122.0 db push --project-ref "$project_ref" --skip-vault --dry-run
if [ "$mode" = apply ]; then
  npx --yes supabase@2.122.0 db push --project-ref "$project_ref" --skip-vault --yes
  npx --yes supabase@2.122.0 functions deploy demo-signup --project-ref "$project_ref" --use-api --yes
  npx --yes supabase@2.122.0 migration list --project-ref "$project_ref"
  echo 'Database migrations and demo-signup deployed. APNs configuration is separate.'
else
  echo 'Plan only. To deploy the reviewed changes, run: sh scripts/deploy-backend.sh apply'
fi
