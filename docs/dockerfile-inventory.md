# Dockerfile inventory

Phase 1, item 3. Snapshot of all nine Dockerfiles after the health-check
and Hadolint hardening pass (see `docs/hadolint-before.txt` /
`docs/hadolint-after.txt` for the linter evidence, and the `fix(docker)`
commit on `test1` for the full change).

| Service | Base image (final stage) | Version pinned? | User | Multi-stage? | Port | HEALTHCHECK calls |
|---|---|---|---|---|---|---|
| auth-service | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes (`maven:3.9-eclipse-temurin-21-alpine` build → jre run) | 8081 | `wget --spider http://localhost:8081/actuator/health` |
| user-service | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8082 | `wget --spider http://localhost:8082/actuator/health` |
| startup-service | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8083 | `wget --spider http://localhost:8083/actuator/health` |
| post-service | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8084 | `wget --spider http://localhost:8084/actuator/health` |
| notification-service | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8086 | `wget --spider http://localhost:8086/actuator/health` |
| api-gateway | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8080 | `wget --spider http://localhost:8080/actuator/health` |
| config-server | `eclipse-temurin:21-jre-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes | 8888 | `wget --spider http://localhost:8888/actuator/health` |
| chat-service | `node:20-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | No — single stage (no compiler/bundler involved; `npm install --omit=dev` already drops devDependencies) | 8085 | `wget --spider http://localhost:8085/health` |
| frontend | `node:20-alpine` | Tag pinned (no digest) | `appuser`, uid 10001 (non-root) | Yes (`deps` → `build` → `runner`) | 3000 | `wget --spider http://127.0.0.1:3000` |

## Notes

- **Version pinning**: all nine pin a tag (e.g. `21-jre-alpine`, `20-alpine`), but none pin a digest (`@sha256:...`). Tags can move if the upstream image is retagged; a digest pin is the stronger guarantee. Not changed in this pass — flagging for a future decision.
- **User**: all nine run as a dedicated non-root account with a fixed numeric UID/GID (10001), confirmed at runtime with `docker exec <container> id`. `USER` still references the account by name (`appuser`) rather than the number, for readable `docker exec`/`docker top`/log output — the UID underneath is what Kubernetes' `runAsUser`/`runAsNonRoot` will check in step 4, and it's fixed either way. See `.hadolint.yaml` for this reasoning against DL3066.
- **Multi-stage**: eight of nine use a build stage separate from the run stage, so the final image has no Maven/JDK compiler or npm dev tooling. `chat-service` is the one exception — it has no compile step at all (plain Express, no TypeScript/bundler), so a second stage would only copy the same files again with no size or attack-surface benefit.
- **HEALTHCHECK**: all nine now use `wget` in JSON-array form (`CMD ["wget", ...]`), confirmed present in both base images (`eclipse-temurin:21-jre-alpine` and `node:20-alpine` both ship BusyBox `wget`). `config-server`'s healthcheck port was corrected from 8088 (never matched anything) to 8888 (the actual bound port) during this pass.
