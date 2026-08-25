# Configuration Reference

| Setting                       | Default              | Description                    |
| ----------------------------- | -------------------- | ------------------------------ |
| `workflow.developmentBranch`  | `staging`            | Development/integration branch |
| `workflow.productionBranch`   | `main`               | Production branch              |
| `branches.release`            | `release/{version}`  | Release branch pattern         |
| `versioning.file`             | `auto`               | Version file location          |
| `release.watchFiles.openapi`  | -                    | OpenAPI spec path              |
| `release.watchFiles.migrations` | -                  | Migration files pattern        |
| `release.watchFiles.schema`   | -                    | Schema file path               |
| `release.generateChangelog`   | `true`               | Generate changelog             |
