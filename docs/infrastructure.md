# CloseTalk — AWS Infrastructure

## Deployment URL

**`https://d34etjxuah5cvp.cloudfront.net/`** (HTTPS via CloudFront)

## Architecture Overview

```
User → CloudFront (HTTPS) → ALB (HTTP) → ECS Fargate (auth-service:8081 / message-service:8082)
                                              → RDS PostgreSQL 17
                                              → DynamoDB (messages, reactions, reads, bookmarks)
                                              → ElastiCache Valkey 8.1
```

## Provisioned Resources

### Networking
| Resource | Detail |
|---|---|
| VPC | `10.0.0.0/16` — ap-south-1 |
| Public Subnets | `10.0.0.0/24` (ap-south-1a), `10.0.1.0/24` (ap-south-1b) |
| Private Subnets | `10.0.10.0/24` (ap-south-1a), `10.0.11.0/24` (ap-south-1b) |
| Internet Gateway | 1 |
| NAT Gateway | 1 (Elastic IP) |
| Route Tables | Public (IGW), Private (NAT) |
| ALB | Internet-facing, HTTP:80 → path-based routing |

### Compute — ECS Fargate

| Service | Port | CPU | Memory | Tasks |
|---|---|---|---|---|
| `auth-service` | 8081 | 512 | 1024 | 1 |
| `message-service` | 8082 | 512 | 1024 | 1 |

- Platform version: 1.4.0 (Linux)
- Network: Private subnets, no public IP
- Auto-scaling: Manual (desired count = 1)
- Deploy strategy: Rolling update (`aws ecs update-service`)

### ALB Routing Rules

| Path Pattern | Target Group | Service |
|---|---|---|
| `/`, `/auth/*`, `/devices/*`, `/groups/*`, `/health` | auth-tg | auth-service:8081 |
| `/messages/*`, `/bookmarks/*`, `/sync/*`, `/ws` | msg-tg | message-service:8082 |
| Default (unmatched) | 404 JSON response | — |

### CloudFront

| Property | Value |
|---|---|
| Domain | `d34etjxuah5cvp.cloudfront.net` |
| Origin | ALB (HTTP:80) |
| Viewer Protocol | HTTP → HTTPS redirect |
| Price Class | North America / Europe / Asia only |
| SSL | CloudFront default certificate (free) |

### Database — RDS PostgreSQL 17

| Property | Value |
|---|---|
| Endpoint | `closetalk-production.cfc280soakcw.ap-south-1.rds.amazonaws.com:5432` |
| Instance | `db.t4g.micro` (Free tier eligible) |
| Storage | 20 GB gp3, encrypted |
| Backup | 1 day retention |
| Public Access | No (private subnet) |

### DynamoDB Tables

| Table | Partition Key | Sort Key | GSI | Billing |
|---|---|---|---|---|
| `closetalk-messages` | `chat_id` | `sort_key` | `message_id` | PAY_PER_REQUEST |
| `closetalk-message-reactions` | `message_id` | `user_emoji` | — | PAY_PER_REQUEST |
| `closetalk-message-reads` | `message_id` | `user_id` | — | PAY_PER_REQUEST |
| `closetalk-bookmarks` | `user_id` | `sort_key` | — | PAY_PER_REQUEST |

All tables have SSE enabled and PITR (point-in-time recovery) enabled.

### Cache — ElastiCache Valkey 8.1

| Property | Value |
|---|---|
| Endpoint | `closetalk-production.kyay52.ng.0001.aps1.cache.amazonaws.com:6379` |
| Node Type | `cache.t4g.micro` |
| Nodes | 1 (replication group) |
| Network | Private subnet |

### Container Registry — ECR

| Repository | URL |
|---|---|
| auth-service | `706489758484.dkr.ecr.ap-south-1.amazonaws.com/closetalk/auth-service` |
| message-service | `706489758484.dkr.ecr.ap-south-1.amazonaws.com/closetalk/message-service` |

### Monitoring — CloudWatch

| Log Group | Retention |
|---|---|
| `/ecs/closetalk/auth-service` | 30 days |
| `/ecs/closetalk/message-service` | 30 days |

### IAM Roles

- `closetalk-ecs-execution-production` — ECR pull, CloudWatch logs
- `closetalk-ecs-task-production` — DynamoDB CRUD access for all 4 tables

## Security Groups

| Group | Rules |
|---|---|
| `closetalk-alb` | Inbound: HTTP (80) from 0.0.0.0/0 |
| `closetalk-ecs` | Inbound: 8081-8082 from ALB security group |
| `closetalk-rds` | Inbound: 5432 from ECS security group |
| `closetalk-elasticache` | Inbound: 6379 from ECS security group |

## CI/CD — GitHub Actions

Workflow: `.github/workflows/deploy.yml`

Triggers: Push to `main` (closetalk_backend/**), or manual dispatch

Steps:
1. Checkout code
2. Configure AWS credentials (IAM user access keys)
3. Login to ECR
4. Build & push Docker image (multi-stage, Go build)
5. Register new ECS task definition
6. Deploy to ECS with rolling update (`wait-for-service-stability`)
7. Verify deployment

## Secrets (GitHub Actions)

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `ECR_AUTH_REPO` | `closetalk/auth-service` |
| `ECR_MESSAGE_REPO` | `closetalk/message-service` |
| `ECS_CLUSTER` | `closetalk-production` |
| `ECS_AUTH_TASK_DEF` | `closetalk-auth-service` |
| `ECS_MESSAGE_TASK_DEF` | `closetalk-message-service` |

## Cost Estimate

| Service | Monthly Cost |
|---|---|
| ECS Fargate (2 × 512/1024) | ~$15 |
| RDS db.t4g.micro | ~$13 |
| ElastiCache cache.t4g.micro | ~$13 |
| DynamoDB (PAY_PER_REQUEST, low traffic) | ~$1 |
| ALB | ~$20 |
| NAT Gateway | ~$32 |
| CloudFront | Free tier |
| **Total** | **~$94/mo** |

## Useful Commands

```bash
# Check service status
aws ecs describe-services --cluster closetalk-production --services auth-service message-service

# Force new deployment
aws ecs update-service --cluster closetalk-production --service auth-service --force-new-deployment

# Check task logs
aws logs tail /ecs/closetalk/auth-service --follow

# Scale up
aws ecs update-service --cluster closetalk-production --service auth-service --desired-count 2
```

## Deployment History

| Date | Change |
|---|---|
| 2026-05-09 | Initial provisioning — VPC, ECS, RDS, DynamoDB, ElastiCache, ALB |
| 2026-05-09 | Dockerfile bugfix — `WORKDIR` / `COPY` collision fixed |
| 2026-05-09 | Added CloudFront distribution for HTTPS |
| 2026-05-09 | ALB default action changed to 404 (was broken HTTPS redirect) |
