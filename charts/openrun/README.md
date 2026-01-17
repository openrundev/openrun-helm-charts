# OpenRun Helm Chart

This Helm chart installs [OpenRun](https://openrun.dev) together with the dependencies that are required for a Kubernetes deployment:

- **Postgres** metadata database. A single-instance StatefulSet is deployed for testing when `postgres.enabled=true` (default). It is recommended to use an external Postgres instance instead.
- **Container registry**. A single `registry:2` instance is deployed when `registry.enabled=true`. Set `registry.enabled=false` and provide your own registry configuration via `config.registry.*` if you already run a registry.
- A `LoadBalancer` service that exposes the OpenRun HTTP API.
- RBAC that allows OpenRun to create Deployments and Services for the applications it manages.

The chart renders an `openrun.toml` using the template stored in `files/openrun.toml.tmpl`. Values referenced inside the template can be overridden without editing the chart.

## Quick start

```bash
helm repo add openrun https://openrundev.github.io/openrun-helm-charts/

# Install a registry for use with OpenRun (for testing)
helm install openrun1 openrun/openrun \
  --namespace openrun --create-namespace --set registry.enabled=true

# Install with a external registry (recommended)
helm install openrun1 openrun/openrun \
  --namespace openrun --create-namespace --set config.registry.url=<registry_url>
```

By default a bundled Postgres StatefulSet is used. It is recommended to use an exteranl managed Postgres. Once all pods become ready you can retrieve the external address of the OpenRun API with:

```bash
kubectl get svc openrun -n openrun
```

## Configuring the registry

OpenRun builds images with Kaniko and pushes them to the registry that is configured inside `openrun.toml`. The bundled registry Deployment is meant for local demos or proof-of-concept installs; for production environments use an external registry service (ECR, GCR, ACR, etc.) or use an existing Harbor deployment.

- To use the bundled registry set `registry.enabled=true`. The service is reachable at `<release>-registry.<namespace>.svc.cluster.local:5000`. HTTP authentication is disabled by default, but you can feed a pre-generated htpasswd entry to require credentials:

  ```yaml
  registry:
    enabled: true
    auth:
      enabled: true
      username: "openrun"
      password: "openrun"
      # Generate the bcrypt hash with: htpasswd -nB openrun
      htpasswd: "openrun:$2y$05$example..."
  ```

  When `registry.auth.enabled=true` the same `username` / `password` defaults are mirrored into `config.registry.*`.

- To use an external registry, disable the in-cluster registry and set the desired registry parameters:

  ```yaml
  registry:
    enabled: false

  config:
    registry:
      url: "registry.example.com:5000"
      project: "openrun"
      username: "ci-bot"
      password: "<token>"
      insecure: false
  ```

The rendered `openrun.toml` is stored in a secret named `{{ include "openrun.configSecretName" . }}` and mounted at `/var/lib/openrun/openrun.toml`.

## Configuring Postgres

The embedded StatefulSet runs a single Postgres instance with persistent storage. It is intended for basic setups and testing—production clusters should either connect to a managed Postgres service or run a fully fledged operator such as CloudNativePG. Customize the in-cluster instance via the `postgres.*` values (storage size, credentials, probes, resources, etc). The OpenRun deployment uses the app user secret to build the Postgres connection string.

To reuse an external Postgres instance disable the embedded cluster and set the connection details:

```yaml
postgres:
  enabled: false

externalDatabase:
  enabled: true
  host: postgres.mycompany.net
  port: 5432
  database: openrun
  username: openrun
  password: "<db-password>"
  # alternatively reference a secret created beforehand
  # existingSecretName: openrun-db-creds
```

The chart fails to render if neither `postgres.enabled` nor `externalDatabase.enabled` are set to `true`.

## RBAC

A dedicated service account is created by default. The chart installs either a `ClusterRole` or namespace-scoped `Role` (switch via `rbac.clusterWide`). The role grants the verbs required for OpenRun to lazily create Deployments, Services, ConfigMaps, Secrets, Jobs, PVCs and related resources on behalf of applications.

## Useful values

| Key                  | Description                                         | Default           |
| -------------------- | --------------------------------------------------- | ----------------- |
| `config.registry.*`  | Registry configuration mirrored into `openrun.toml` | see `values.yaml` |
| `postgres.enabled`   | Deploy the bundled Postgres StatefulSet             | `true`            |
| `externalDatabase.*` | Connection info for an existing Postgres instance   | disabled          |
| `registry.enabled`   | Deploy the in-cluster `registry:2` instance         | `false`           |

Refer to `values.yaml` for the full list of tunables.
