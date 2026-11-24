# Call matrix: who calls whom

Built from the services' source and config, not from memory. Each edge
names the file that proves it. This is the input for the Istio
AuthorizationPolicies (Phase 3, step 6): one policy per callee, naming
the caller ServiceAccounts allowed in.

Istio identifies a caller by its ServiceAccount, written as
`cluster.local/ns/foundersync/sa/<name>`. The shared chart creates one
ServiceAccount per release, named after the release (`auth-service`,
`user-service`, and so on).

## HTTP between pods

| Caller | Callee | Port | Request | Evidence |
|---|---|---|---|---|
| entry point (Traefik or Istio gateway) | frontend | 3000 | `/` | `k3d/ingress.yaml` |
| entry point | api-gateway | 8080 | `/api/**`, `/socket.io/**` | `k3d/ingress.yaml` |
| api-gateway | auth-service | 8081 | `/api/auth/**` | `GatewayConfig.java` |
| api-gateway | user-service | 8082 | `/api/users/**` | `GatewayConfig.java` |
| api-gateway | startup-service | 8083 | `/api/startups/**`, `/api/admin/startups/**` | `GatewayConfig.java` |
| api-gateway | post-service | 8084 | `/api/posts/**` | `GatewayConfig.java` |
| api-gateway | chat-service | 8085 | `/api/chat/**`, `/socket.io/**` | `GatewayConfig.java` |
| api-gateway | notification-service | 8086 | `/api/notifications/**` | `GatewayConfig.java` |
| post-service | user-service | 8082 | `GET /api/users/{id}` | `post_service/client/UserServiceClient.java` |
| notification-service | user-service | 8082 | `GET /api/users/{id}` | `notification_service/client/UserServiceClient.java` (see note 1) |
| chat-service | user-service | 8082 | `GET /api/users/{id}` | `chat-service/src/publishers/notificationPublisher.js` |
| api-gateway, auth, user, startup, post, notification | config-server | 8888 | config fetch at startup | `SPRING_CONFIG_IMPORT` in each values file, `bootstrap.yml` for the gateway |

No other service-to-service HTTP call exists in the source. I searched for
RestTemplate, WebClient, RestClient, Feign and axios. Nothing calls
post-service except the gateway.

## RabbitMQ (AMQP)

| Service | Publishes | Consumes |
|---|---|---|
| auth-service | user registered, user banned/unbanned | none |
| user-service | none | `user.registered.queue`, `user.banned.queue` |
| startup-service | `foundersync.startup.exchange` (9 event types) | none |
| post-service | `foundersync.post.exchange` (liked, commented) | none |
| chat-service | `foundersync.notification.queue` | `foundersync.chat.queue` (bound to the startup exchange) |
| notification-service | none | `foundersync.notification.queue` (also bound to both exchanges) |

Every service that appears here connects to the broker as a client.
Nothing connects to another service through RabbitMQ directly.

## Data stores

| Service | Store |
|---|---|
| auth-service | Postgres `auth_db` |
| user-service | Postgres `users_db` |
| startup-service | Postgres `startup_db` |
| post-service | Postgres `post_service_db` |
| notification-service | Postgres `notification_service_db` |
| chat-service | MongoDB `chatdb` |
| api-gateway, frontend, config-server | none |

## Allowed callers per service (input for the policies)

| Callee | Allowed caller ServiceAccounts |
|---|---|
| frontend | entry point |
| api-gateway | entry point |
| auth-service | api-gateway |
| user-service | api-gateway, post-service, notification-service, chat-service |
| startup-service | api-gateway |
| post-service | api-gateway |
| chat-service | api-gateway |
| notification-service | api-gateway |
| config-server | api-gateway, auth-service, user-service, startup-service, post-service, notification-service |

The databases and RabbitMQ are not in this table because whether they sit
inside the mesh is still an open decision with A.

## Notes

1. **notification-service to user-service is probably not working today.**
   The Feign client reads `services.user-service.url` and falls back to
   `http://localhost:8082`. No config file or values file sets that
   property (only post-service has an equivalent, `user-service.url`).
   The call is wrapped in a try/catch that returns a fallback name, so it
   fails quietly. This comes from reading the code. I have not confirmed it in the
   running pod's logs. The policy still lists the edge because it is the
   intended one.
2. **The three callers of `GET /api/users/{id}` send no Authorization
   header.** That is one of the open user-service endpoints. If it is
   later made to require a token, these three internal calls break unless
   they are changed too.
3. **The config-server edge is broad on purpose.** Restricting it is
   worth doing: config-server serves the JWT secret in plaintext to any
   caller (see `scripts/attacks/attack-network.sh`).
