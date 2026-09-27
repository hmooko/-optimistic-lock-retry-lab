# Optimistic Lock Retry Lab

A Spring Boot benchmark for studying how optimistic-lock retry policies behave as data contention increases.

## Compared strategies

| ID | Policy |
| --- | --- |
| PESSIMISTIC | DB pessimistic write lock |
| OPT_IMMEDIATE | retry immediately |
| OPT_FIXED | fixed 20 ms backoff |
| OPT_FIXED_JITTER | fixed backoff with +/-50% uniform jitter |
| OPT_EXPONENTIAL | 5, 10, 20, 40, 80 ms capped exponential backoff |
| OPT_EXPONENTIAL_JITTER | exponential backoff with +/-50% uniform jitter |

All optimistic strategies allow at most 5 retries, so one request can execute at most 6 transaction attempts.

## Experiment design

The offered request rate stays constant. Data contention is increased by shrinking the hot set:

| Contention | Hot set |
| --- | ---: |
| Low | 100 products |
| Medium | 20 products |
| High | 5 products |
| Extreme | 1 product |

This avoids conflating higher server load with higher data contention.

Primary metrics:

1. successful throughput
2. p99 end-to-end purchase latency (measurement phase only)
3. retry amplification = total retries / successful requests
4. final failure rate after retry exhaustion

## Stack

- Java 21
- Spring Boot 4.1.1
- Spring Data JPA / Hibernate
- MySQL 8.4 / InnoDB
- k6

Spring Boot 4.1.1 is the current stable Spring Boot release used by this project.

## Transaction boundary

PurchaseService owns the retry loop, while PurchaseTransactionService owns the transactional methods.

Every optimistic retry therefore calls another Spring bean and starts a fresh transaction instead of retrying inside an already-failed transaction.

## Local run

Start MySQL:

    docker compose up -d mysql

Run the application:

    mvn spring-boot:run

Reset benchmark data:

    curl -X POST "http://localhost:8080/api/admin/reset?productCount=100&stock=1000000"

Run one benchmark:

    k6 run \
      -e RATE=400 \
      -e HOT_SET=5 \
      -e STRATEGY=OPT_EXPONENTIAL_JITTER \
      k6/benchmark.js

The 400 RPS value is only a local example. The paper should use a calibrated load.

## Calibration

Run:

    bash scripts/calibrate.sh

Use a request rate below the non-contention saturation point. The intended procedure is:

1. use HOT_SET=1000 to make collisions negligible
2. test increasing rates
3. reject rates that cause k6 dropped iterations or infrastructure saturation
4. select about 80% of the highest stable rate for the main experiment

## Full matrix

After calibration:

    RATE=500 bash scripts/run-matrix.sh

The initial matrix is:

    6 strategies x 4 hot-set sizes x 5 repetitions = 120 runs

Each repetition randomizes the 24 strategy/hot-set combinations to reduce time-order effects.

## Server allocation

Recommended allocation inside the 8 vCPU / 16 GB RAM / 100 GB storage limit:

| Role | vCPU | RAM | Storage |
| --- | ---: | ---: | ---: |
| k6 load generator | 2 | 2 GB | 15 GB |
| Spring Boot application | 2 | 4 GB | 20 GB |
| MySQL | 3 | 8 GB | 55 GB |

The remaining 1 vCPU, 2 GB RAM, and 10 GB storage are left as headroom.

Initial runtime settings:

- application JVM heap: 2 GB
- HikariCP maximum pool size: 32
- Tomcat max threads: 200
- MySQL transaction isolation: READ COMMITTED
- planned MySQL buffer pool: 4 GB on the experiment DB server

## Repository layout

    src/main/java/.../domain      Product and repository
    src/main/java/.../purchase    lock, transaction, retry orchestration
    src/main/java/.../retry       retry timing policy
    src/main/java/.../admin       benchmark reset endpoint
    k6/benchmark.js               constant-arrival-rate workload
    scripts/calibrate.sh          offered-load calibration
    scripts/run-matrix.sh         full experiment matrix

## Next steps

- add an integration test proving no lost updates for all six strategies
- randomize the final experiment run order
- add CSV aggregation for median/error bars
- add Prometheus/Grafana only as secondary diagnostics
- pin the final JVM/MySQL OS-level settings used for the paper
