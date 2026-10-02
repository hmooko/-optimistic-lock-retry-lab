# Optimistic Lock Retry Lab

A reproducible Spring Boot benchmark for studying optimistic-lock retry policies under increasing data contention.

## Compared strategies

| ID | Policy |
| --- | --- |
| PESSIMISTIC | DB pessimistic write lock |
| OPT_IMMEDIATE | retry immediately |
| OPT_FIXED | fixed 20 ms backoff |
| OPT_FIXED_JITTER | fixed backoff with +/-50% uniform jitter |
| OPT_EXPONENTIAL | 5, 10, 20, 40, 80 ms capped exponential backoff |
| OPT_EXPONENTIAL_JITTER | exponential backoff with +/-50% uniform jitter |

All optimistic strategies allow at most 5 retries.

## Experiment topology

Use three separate Linux servers in the same private network.

| Server | Resource budget | Container |
| --- | ---: | --- |
| Load | 2 vCPU / 2 GB / 15 GB | k6 |
| App | 2 vCPU / 4 GB / 20 GB | Spring Boot |
| DB | 3 vCPU / 8 GB / 55 GB | MySQL |
| Headroom | 1 vCPU / 2 GB / 10 GB | unused |

Suggested private IPs:

    Load  10.0.0.10
    App   10.0.0.20
    DB    10.0.0.30

The experiment containers use Docker host networking.

## Disposable experiment credentials

This repository intentionally contains fixed credentials for this short-lived isolated benchmark:

    database: retry_lab
    username: retry_lab
    password: retry-lab-2026
    root password: root-retry-lab-2026

These values are not secrets and must not be reused for any real service or account.

Network isolation is still required:

- DB TCP 3306: allow only from the App server private IP.
- App TCP 8080: allow only from the Load server private IP and, if necessary, the administrator IP.
- Do not expose MySQL TCP 3306 to the public Internet.

No App/DB `.env` file is required.

## Pinned experiment environment

- Java runtime: Eclipse Temurin 21.0.12_8 JRE
- build: Maven 3.9.16 + Java 21
- Spring Boot: 4.1.1
- MySQL: 8.4.11
- k6: 2.3.0
- k6 calibration defaults: 500 pre-allocated VUs (maximum 1000 per scenario)
- k6 main matrix: 1000 pre-allocated VUs (maximum 3000 per scenario)
- Node Exporter: 1.12.1
- Prometheus: 3.15.0
- Grafana OSS: 13.2.2
- result aggregation: Python 3.12 container

## 1. Install Docker and Git

Install Docker Engine, Docker Compose plugin, and Git on all three servers.

After Docker installation, make sure the experiment user can run:

    docker ps
    docker compose version

Clone the repository on every server:

    git clone https://github.com/hmooko/optimistic-lock-retry-lab.git retry-lab
    cd retry-lab

Use the same Git revision on all three servers.

## 2. Database server

On the DB server:

    cd retry-lab
    sudo mkdir -p /data/mysql

Pull and start MySQL:

    docker compose -f deploy/db/compose.yml pull
    docker compose -f deploy/db/compose.yml up -d

Check:

    docker compose -f deploy/db/compose.yml ps
    docker logs retry-lab-mysql --tail 50

The DB experiment configuration is fixed in Git:

- MySQL 8.4.11
- 3 CPU / 8 GB container limit
- READ COMMITTED
- 4 GB InnoDB buffer pool
- `innodb_flush_log_at_trx_commit=1`
- binary log disabled
- data directory: `/data/mysql`

If the DB disk is mounted somewhere else, override only the path:

    MYSQL_DATA_DIR=/other/path     docker compose -f deploy/db/compose.yml up -d

## 3. Application server

The default DB host is `10.0.0.30`.

If your DB server uses that address:

    docker compose -f deploy/app/compose.yml up -d --build

If the DB private IP is different:

    DB_HOST=10.0.1.30     docker compose -f deploy/app/compose.yml up -d --build

Verify:

    docker compose -f deploy/app/compose.yml ps
    docker logs retry-lab-app --tail 100
    curl http://127.0.0.1:8080/actuator/health

The App experiment settings are fixed in Git:

- 2 CPU / 4 GB container limit
- JVM heap 2 GB
- HikariCP max pool 32
- HikariCP minimum idle 8
- Tomcat max threads 200
- max retries 5
- fixed backoff 20 ms
- exponential base 5 ms
- exponential cap 80 ms
- jitter +/-50%

## 4. Load server

Pull the pinned k6 and Python images:

    docker compose -f deploy/load/compose.yml pull

Check k6:

    bash scripts/run-k6-docker.sh version

No host k6 or Python installation is required.

## 5. Smoke test

Assuming the App server is `10.0.0.20`:

    BASE_URL=http://10.0.0.20:8080     bash scripts/smoke-test.sh

Check:

    cat results/smoke.json

Make sure `droppedIterations` is 0.

## 6. Calibration

Run:

    BASE_URL=http://10.0.0.20:8080     bash scripts/calibrate.sh

Default offered rates:

    100 200 300 400 500 600 RPS

If 600 RPS is still well below saturation:

    BASE_URL=http://10.0.0.20:8080     RATES="800 1000 1200 1400"     bash scripts/calibrate.sh

Calibration uses `HOT_SET=1000` and `OPT_IMMEDIATE`. k6 pre-allocates 500 VUs so transient VU allocation does not create artificial dropped iterations before the target system is saturated.

Choose approximately 80% of the highest stable offered rate while checking:

- measurement-phase `droppedIterations = 0`
- Load CPU is not saturated
- App CPU is not saturated
- DB CPU and I/O are not saturated

The structured result JSON reports:
- `droppedIterations`: measurement-phase dropped iterations only
- `warmupDroppedIterations`: warm-up dropped iterations
- `totalDroppedIterations`: warm-up + measurement dropped iterations

After choosing a candidate RATE, validate it under the worst contention level before starting the full matrix:

    BASE_URL=http://10.0.0.20:8080 RATE=1000 \
      bash scripts/run-worst-case-pilot.sh

The worst-case pilot runs all six strategies at `HOT_SET=1`, using 1000 pre-allocated VUs and a maximum of 3000 VUs per scenario by default. All six runs must finish with measurement-phase `droppedIterations = 0`. Override `PRE_ALLOCATED_VUS` or `MAX_VUS` only during pilot validation if necessary, and keep the chosen values fixed for the measured experiment.

After choosing the final RATE and VU settings, do not change the experiment configuration until all measured runs are complete.

## 7. Optional live monitoring from macOS

For the experiment setup used in this repository, Prometheus and Grafana run on the MacBook while lightweight Node Exporter containers run on the three Linux servers. Metrics travel through SSH tunnels, so ports 9100 and 8080 do not need to be opened publicly.

Prerequisites on the MacBook:

- Docker Desktop is running.
- VPN access to the experiment private network is active.
- SSH key authentication works for the aliases `retry-app`, `retry-db`, and `retry-load`.

Update all three server repositories to the latest `main` revision and install or refresh Node Exporter:

    bash scripts/setup-monitoring-exporters.sh

The setup script connects to `retry-app`, `retry-db`, and `retry-load`, requires each remote checkout to be on a clean `main` branch, runs `git pull --ff-only origin main`, prints the resulting Git revision, and then starts Node Exporter. If a server has tracked local changes or is on another branch, the script stops instead of silently changing the experiment environment.

Start the SSH tunnels, Prometheus, and Grafana:

    bash scripts/start-monitoring.sh

Open:

    Grafana:    http://localhost:3000
    Prometheus: http://localhost:9090/targets

Grafana login:

    username: admin
    password: retry-lab-grafana

The Prometheus data source and the `Retry Lab Monitoring` dashboard are provisioned automatically. The dashboard includes host CPU, memory, disk I/O, network I/O, JVM heap, HikariCP connections, GC activity, and scrape-target status.

Check tunnel status:

    bash scripts/monitoring-tunnels.sh status

Stop local monitoring:

    bash scripts/stop-monitoring.sh

If different SSH aliases are used, override them:

    APP_SSH=my-app DB_SSH=my-db LOAD_SSH=my-load \
      bash scripts/setup-monitoring-exporters.sh

    APP_SSH=my-app DB_SSH=my-db LOAD_SSH=my-load \
      bash scripts/start-monitoring.sh

Monitoring metrics are diagnostic only. Paper result metrics such as throughput, p99 latency, retry amplification, and final failure rate continue to come from the k6 result JSON files. Keep the monitoring configuration unchanged across all measured runs.

## 8. Record environment

Before the final experiment:

DB server:

    bash scripts/record-docker-environment.sh db

App server:

    bash scripts/record-docker-environment.sh app

Load server:

    bash scripts/record-docker-environment.sh load

Keep the generated `results/environment/` files with the experiment artifacts.

## 9. Main experiment

Validated final offered rate: 800 RPS. The worst-case HOT_SET=1 pilot passed all six strategies with zero measurement-phase dropped iterations using 1000 pre-allocated VUs and a maximum of 3000 VUs per scenario.

Run:

    BASE_URL=http://10.0.0.20:8080 \
      RATE=800 \
      bash scripts/run-matrix.sh

The main-matrix script defaults to the validated VU capacity:

    PRE_ALLOCATED_VUS=1000
    MAX_VUS=3000

These values may be overridden explicitly, but they should remain fixed across all measured runs.

The matrix is:

    6 strategies x 4 contention levels x 5 repetitions = 120 runs

Contention levels:

| Level | Hot set |
| --- | ---: |
| Low | 100 |
| Medium | 20 |
| High | 5 |
| Extreme | 1 |

Each run uses:

- 20 s warm-up
- 60 s measurement
- 10 s pause

The 24 strategy/hot-set combinations are shuffled for each repetition.

All final runs should have measurement-phase `droppedIterations = 0`. Warm-up dropped iterations are recorded separately and are not used as the validity threshold.

## 10. Aggregate results

Run on the Load server:

    bash scripts/aggregate-results-docker.sh

Outputs:

    results/runs.csv
    results/summary.csv

The summary contains median, mean, standard deviation, Q1, and Q3 for:

- successful throughput
- p99 latency
- retry amplification
- final failure rate

Recommended paper figures:

1. contention vs retry amplification
2. contention vs successful throughput
3. contention vs p99 latency

## Correctness verification

CI verifies:

- Java unit tests
- MySQL Testcontainers concurrency integration tests
- result aggregation tests
- shell syntax
- Docker Compose configuration
- application Docker image build

The concurrency integration test checks all six strategies and verifies that committed stock/version changes match successful transactions.

## Repository layout

    deploy/app/                    Spring Boot Docker deployment
    deploy/db/                     MySQL Docker deployment
    deploy/load/                   k6/Python Docker tools
    k6/benchmark.js                constant-arrival-rate workload
    scripts/smoke-test.sh          smoke test
    scripts/calibrate.sh           load calibration
    scripts/run-worst-case-pilot.sh six-strategy HOT_SET=1 validation
    scripts/run-matrix.sh          120-run experiment matrix
    scripts/aggregate-results-docker.sh
    scripts/record-docker-environment.sh
