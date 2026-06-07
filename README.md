# experiments-with-concourse

Experimenting with Concourse CI.

## Objectives

| Objective                    | Achieved |
| ---------------------------- | -------- |
| GitHub-triggered pipeline.   | ❌       |
| AWS auth with OpenID Connect | ❌       |

## Setup Notes

1. Run Concourse: `docker compose up`

2. Install [fly CLI](http://localhost:8080/download-fly)

3. CLI auth: `fly -t tutorial login -c http://localhost:8080 -u test -p test`

4. List workers: `fly -t tutorial workers`

5. Register pipeline: `fly -t tutorial set-pipeline -p hello-world -c concourse/hello-world.yml`

6. Unpause new pipeline: `fly -t tutorial unpause-pipeline -p hello-world`

7. Run pipeline: `fly -t tutorial trigger-job --job hello-world/hello-world-job --watch`

## Recommended VS Code Extensions

- [Concourse CI Pipeline Editor](https://marketplace.visualstudio.com/items?itemName=vmware.vscode-concourse) (Requires Java)
