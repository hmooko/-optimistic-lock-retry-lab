# Optimistic Lock Retry Lab

A reproducible Spring Boot benchmark for studying how optimistic-lock retry policies behave as data contention increases.

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

Primary metrics:

1. successful throughput
2. p99 end-to-end purchase latency
3. retry amplification = total retries / successful requests
4. final failure rate after retry exhaustion

## Three-server Docker topology

The paper experiment uses three separate Linux servers. Each server runs only its assigned experiment container.

| Server | Resource budget | Container |
| --- | ---: | --- |
| Load generator | 2 vCPU / 2 GB RAM / 15 GB | k6 |
| Application | 2 vCPU / 4 GB RAM / 20 GB | Spring Boot |
| Database | 3 vCPU / 8 GB RAM / 55 GB | MySQL |
| Reserved headroom | 1 vCPU / 2 GB RAM / 10 GB | unused |

Experiment images are pinned in the deployment files:

- application runtime: Eclipse Temurin 21.0.12_8 JRE
- application build: Maven 3.9.16 + Java 21
- database: MySQL 8.4.11
- load generator: Grafana k6 2.3.0
- result aggregation: Python 3.12 container

The app, DB, and k6 experiment containers use Docker host networking. This deployment is intended for Linux experiment servers and avoids adding Docker bridge/NAT overhead to the measured request path.

The root-level `docker-compose.yml` remains a local-development convenience only. Do not use it for the paper experiment.

## Network rules

Use private server addresses and restrict inbound traffic at the cloud firewall/security-group level.

- DB server TCP 3306: allow only from the Application server private IP.
- Application server TCP 8080: allow only from the Load server private IP and, if needed, the administrator IP.
- Load server: no experiment-related inbound port is required.

## 1. Database server

Clone the repository into a normal directory name:

    git clone https://github.com/hmooko/-optimistic-lock-retry-lab.git retry-lab
    cd retry-lab

Prepare the DB environment:

    cp deploy/db/.env.example deploy/db/.env

Edit `deploy/db/.env` and set strong experiment passwords. If the 55 GB DB disk is mounted somewhere other than `/data/mysql`, change `MYSQL_DATA_DIR`.

Prepare the storage directory:

    sudo mkdir -p /data/mysql

Pull and start MySQL:

    docker compose       --env-file deploy/db/.env       -f deploy/db/compose.yml       pull

    docker compose       --env-file deploy/db/.env       -f deploy/db/compose.yml       up -d

Check container state:

    docker compose       --env-file deploy/db/.env       -f deploy/db/compose.yml       ps

The experiment DB settings are fixed to:

- InnoDB
- READ COMMITTED
- 4 GB InnoDB buffer pool
- `innodb_flush_log_at_trx_commit=1`
- binary log disabled
- 3 CPU / 8 GB container limit

## 2. Application server

Clone the same revision:

    git clone https://github.com/hmooko/-optimistic-lock-retry-lab.git retry-lab
    cd retry-lab

Prepare configuration:

    cp deploy/app/.env.example deploy/app/.env

Edit `DB_URL` in `deploy/app/.env` so it points to the DB server private IP. For example:

    DB_URL=jdbc:mysql://10.0.0.30:3306/retry_lab?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC

Set `DB_PASSWORD` to the same value used on the DB server.

Build and start the application entirely through Docker:

    docker compose       --env-file deploy/app/.env       -f deploy/app/compose.yml       up -d --build

Verify health:

    curl http://127.0.0.1:8080/actuator/health

The application experiment settings are fixed to:

- Java heap: 2 GB
- container: 2 CPU / 4 GB
- HikariCP max pool: 32
- HikariCP minimum idle: 8
- Tomcat max threads: 200
- optimistic retry limit: 5
- fixed backoff: 20 ms
- exponential backoff: 5 / 10 / 20 / 40 / 80 ms
- jitter ratio: +/-50%

## 3. Load-generator server

Clone the same revision:

    git clone https://github.com/hmooko/-optimistic-lock-retry-lab.git retry-lab
    cd retry-lab

Pull the load and aggregation images:

    docker compose -f deploy/load/compose.yml pull

Confirm the pinned k6 version without installing k6 on the host:

    bash scripts/run-k6-docker.sh version

Only Docker, Docker Compose, Git, Bash, and normal Linux utilities are required on the load server.

## 4. Smoke test

Assume the Application server private IP is `10.0.0.20`.

Run:

    BASE_URL=http://10.0.0.20:8080     bash scripts/smoke-test.sh

Verify:

    cat results/smoke.json

The result must contain the strategy metadata and:

- successCount
- failureCount
- retryCount
- throughputPerSecond
- p99LatencyMs
- retryAmplification
- failureRate
- droppedIterations

Do not start the main experiment until the smoke test succeeds.

## 5. Calibration

Calibration finds a request rate below infrastructure saturation while contention is negligible.

Run the default sequence:

    BASE_URL=http://10.0.0.20:8080     bash scripts/calibrate.sh

The default rates are:

    100 200 300 400 500 600 RPS

If 600 RPS is still clearly below saturation, extend the search without editing the script:

    BASE_URL=http://10.0.0.20:8080     RATES="800 1000 1200 1400"     bash scripts/calibrate.sh

Calibration uses `HOT_SET=1000` and `OPT_IMMEDIATE`.

During calibration, verify that:

- k6 `droppedIterations` remains 0
- Load server is not CPU-saturated
- Application server is not CPU-saturated
- DB server is not CPU/I/O-saturated

Choose approximately 80% of the highest stable offered rate as the fixed main-experiment `RATE`.

Once the main rate is selected, do not change server sizes, image versions, JVM settings, DB settings, pool size, backoff parameters, or retry limit until the dataset is complete.

## 6. Record the environment

After all three containers are running and before the final dataset is collected, record each server separately:

On the DB server:

    bash scripts/record-docker-environment.sh db

On the Application server:

    bash scripts/record-docker-environment.sh app

On the Load server:

    bash scripts/record-docker-environment.sh load

Each command writes a file under `results/environment/`. Keep these files with the experiment artifacts so the exact Docker image digests and Docker versions used in the paper can be reported.

## 7. Main experiment

Suppose calibration selected 800 RPS:

    BASE_URL=http://10.0.0.20:8080     RATE=800     bash scripts/run-matrix.sh

The matrix is:

    6 strategies x 4 hot-set sizes x 5 repetitions = 120 runs

Each run uses:

- 20 s warm-up
- 60 s measurement
- 10 s pause before the next condition

The 24 strategy/hot-set combinations are shuffled for each repetition.

Expected result names look like:

    results/PESSIMISTIC_hot100_run1.json
    results/OPT_FIXED_JITTER_hot5_run3.json
    results/OPT_EXPONENTIAL_JITTER_hot1_run5.json

All final runs should have `droppedIterations = 0`. Investigate and rerun invalid conditions rather than silently including a run where the load generator failed to maintain the offered rate.

## 8. Aggregate the dataset

No host Python installation is required.

Run:

    bash scripts/aggregate-results-docker.sh

This creates:

- `results/runs.csv`: one row per measured run
- `results/summary.csv`: strategy/hot-set summary with n, median, mean, standard deviation, Q1, and Q3

The paper graphs should primarily use the median across the five repetitions, with Q1-Q3 shown as variability when space allows.

Recommended figures:

1. contention vs retry amplification
2. contention vs successful throughput
3. contention vs p99 latency

Failure rate can be presented as a compact table.

## Correctness verification

The test suite uses MySQL Testcontainers and verifies all six strategies under concurrent updates:

- final stock = initial stock - successful transactions
- JPA version = number of successful committed updates
- retry-exhausted requests do not mutate stock

CI additionally validates the Docker deployment files and builds the experiment application image.

## Repository layout

    deploy/app/                    application Docker deployment
    deploy/db/                     MySQL Docker deployment
    deploy/load/                   k6/Python Docker tools
    src/main/java/.../domain       product entity/repository
    src/main/java/.../purchase     locking and retry orchestration
    src/main/java/.../retry        retry timing policy
    k6/benchmark.js                constant-arrival-rate workload
    scripts/smoke-test.sh          Docker smoke test
    scripts/calibrate.sh           Docker calibration
    scripts/run-matrix.sh          Docker full experiment matrix
    scripts/aggregate-results-docker.sh
    scripts/record-docker-environment.sh
