package io.github.hmooko.retrylab.purchase;

import static org.assertj.core.api.Assertions.assertThat;

import io.github.hmooko.retrylab.admin.BenchmarkAdminService;
import io.github.hmooko.retrylab.domain.Product;
import io.github.hmooko.retrylab.domain.ProductRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@Testcontainers
class PurchaseConcurrencyIntegrationTest {

    private static final long INITIAL_STOCK = 10_000L;
    private static final int CONCURRENT_REQUESTS = 24;

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("retry_lab")
            .withUsername("retry_lab")
            .withPassword("retry_lab")
            .withCommand("--transaction-isolation=READ-COMMITTED");

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        registry.add("benchmark.retry.max-retries", () -> 5);
    }

    @Autowired
    PurchaseService purchaseService;

    @Autowired
    BenchmarkAdminService benchmarkAdminService;

    @Autowired
    ProductRepository productRepository;

    static Stream<PurchaseStrategy> strategies() {
        return Stream.of(PurchaseStrategy.values());
    }

    @ParameterizedTest(name = "{0} preserves stock and version under concurrent updates")
    @MethodSource("strategies")
    void noLostUpdates(PurchaseStrategy strategy) throws Exception {
        benchmarkAdminService.reset(1, INITIAL_STOCK);

        AtomicInteger successes = new AtomicInteger();
        AtomicInteger retryExhausted = new AtomicInteger();
        CountDownLatch ready = new CountDownLatch(CONCURRENT_REQUESTS);
        CountDownLatch start = new CountDownLatch(1);

        ExecutorService executor = Executors.newFixedThreadPool(CONCURRENT_REQUESTS);
        try {
            List<Future<Void>> futures = new ArrayList<>();

            for (int i = 0; i < CONCURRENT_REQUESTS; i++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(10, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("timed out waiting for concurrent start");
                    }

                    try {
                        purchaseService.purchase(1L, strategy);
                        successes.incrementAndGet();
                    } catch (RetryExhaustedException expected) {
                        retryExhausted.incrementAndGet();
                    }
                    return null;
                }));
            }

            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            start.countDown();

            for (Future<Void> future : futures) {
                unwrap(future);
            }
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue();
        }

        Product product = productRepository.findById(1L).orElseThrow();

        assertThat(successes.get() + retryExhausted.get())
                .isEqualTo(CONCURRENT_REQUESTS);
        assertThat(successes.get()).isPositive();
        assertThat(product.getStock())
                .isEqualTo(INITIAL_STOCK - successes.get());
        assertThat(product.getVersion())
                .isEqualTo((long) successes.get());
    }

    private static void unwrap(Future<Void> future) throws Exception {
        try {
            future.get(20, TimeUnit.SECONDS);
        } catch (ExecutionException executionException) {
            Throwable cause = executionException.getCause();
            if (cause instanceof Exception exception) {
                throw exception;
            }
            throw executionException;
        }
    }
}
