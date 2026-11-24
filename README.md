# FoundersSync: Securing Inter-Microservice Communication


![Status](https://img.shields.io/badge/status-in%20development-blue?style=flat-square)
![Kubernetes](https://img.shields.io/badge/Kubernetes-k3d-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-mTLS%20STRICT-466BB0?style=flat-square&logo=istio&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)
![Semgrep](https://img.shields.io/badge/SAST-Semgrep-1B2A49?style=flat-square)
![Trivy](https://img.shields.io/badge/Scan-Trivy-1904DA?style=flat-square)
![Gitleaks](https://img.shields.io/badge/Secrets-Gitleaks-DC143C?style=flat-square)
![OWASP](https://img.shields.io/badge/OWASP-Top%2010-000000?style=flat-square&logo=owasp&logoColor=white)



A DevSecOps project that secures the communication between the microservices of **FoundersSync**, a platform connecting young co-founders. The application is deployed on Kubernetes and protected by an authentication and authorization module built around identity, encryption, and least privilege.

> ENSIAS, 3rd year Software Engineering, DevSecOps project, 2026–2027

## Overview

FoundersSync is made of nine deployable components: six microservices (five Spring Boot, one Node.js), an API gateway, a configuration server, and a Next.js frontend. They rely on PostgreSQL, MongoDB, and RabbitMQ.

In its original form, the application had several weaknesses in how its components talk to each other: a shared and public JWT secret, unauthenticated internal calls, default credentials, and unencrypted messaging. This project addresses them in layers, without redesigning the application.

## Security Approach

The module protects the application on two complementary levels.

**User layer** answers *who is the person and what can they do?*
- JWT tokens issued by a dedicated authentication service
- Token verification in each service
- Role-based access (USER, ADMIN) and an ownership rule

**Service layer** answers *which service is calling and may it reach its target?*
- Mutual TLS between services (Istio service mesh)
- Authorization policies derived from the call matrix between services
- Default-deny network policies
- Secrets kept out of the repository
- Encrypted messaging (RabbitMQ over TLS)

The design follows the **Zero Trust** principle: no implicit trust based on network position, and every request is verified.

## Architecture

```
Browser
   |
Ingress (Istio gateway)
   |
API Gateway --> Microservices (auth, user, startup, post, notification, chat)
                    |                     |
              PostgreSQL / MongoDB     RabbitMQ (TLS)
```

All services run in a Kubernetes namespace with a sidecar proxy per pod, strict mTLS, and per-service authorization policies.

## Project Phases

1. **Foundations**: reproducible baseline, automated CI checks, container images, and attack scripts run against the original application.
2. **Local Kubernetes**: migration from Docker Compose to a k3d cluster, with Helm charts for data components and services.
3. **Security hardening**: dedicated credentials, Istio mTLS and authorization policies, network isolation, and encrypted messaging.
4. **Validation**: the same attack scenarios replayed against the secured cluster to prove the improvement.

## DevSecOps Pipelines

Automated GitHub Actions workflows run on every change:

| Concern | Tooling |
|---|---|
| Secret detection | Gitleaks |
| Static code analysis | Semgrep |
| Dependency and image scanning | Trivy |
| Dockerfile quality | Hadolint |
| Build, tests, and images | Maven, npm, Docker Buildx |
| Kubernetes manifest validation | Helm lint, kubeconform |

## Results

Automated attacks were replayed before and after hardening:

| | Before | After |
|---|---|---|
| Successful attacks | 12 / 13 | 2 / 15 |

The two remaining attacks involve an attacker who already holds the shared signing secret, which is documented as a known limitation.

## Known Limitations

- Shared symmetric JWT secret (HMAC); asymmetric signing (RS256) is the recommended next step
- Access tokens remain valid until expiry (no revocation list)
- Database and message broker accounts are shared across services
- Kubernetes Secrets are base64-encoded, not encrypted at rest
- Image vulnerability scans are informative and do not block the pipeline

## Technology Stack

**Application**: Spring Boot, Spring Security, Node.js, Socket.IO, Next.js  
**Data and messaging**: PostgreSQL, MongoDB, RabbitMQ  
**Platform**: Docker, Kubernetes (k3d), Helm, Istio  
**CI/CD and security**: GitHub Actions, Gitleaks, Semgrep, Trivy, Hadolint

## Repository Layout

```
.
├── services/        # Microservices
├── infrastructure/  # API gateway and config server
├── frontend/        # Next.js application
├── charts/          # Helm charts
├── scripts/         # Smoke test and attack scripts
├── evidence/        # Attack results (before / after)
├── .github/         # CI/CD workflows
└── docs/            # Project report
```

## Documentation

The full report (architecture, justification of choices, deployment process, validation, and trade-offs) is available in the `docs/` folder.

## Authors

- Alae Labhal
- Aya Mlouki

Supervised by **Driss Bouzidi**, ENSIAS.
