package io.github.hmooko.retrylab.purchase;

import io.github.hmooko.retrylab.retry.RetryDelayPolicy;
import io.github.hmooko.retrylab.retry.RetrySettings;
import java.util.concurrent.TimeUnit;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;

@Service
public class PurchaseService {
    private final PurchaseTransactionService transactionService;
    private final RetryDelayPolicy retryDelayPolicy;
    private final RetrySettings retrySettings;

    public PurchaseService(
            PurchaseTransactionService transactionService,
            RetryDelayPolicy retryDelayPolicy,
            RetrySettings retrySettings
    ) {
        this.transactionService = transactionService;
        this.retryDelayPolicy = retryDelayPolicy;
        this.retrySettings = retrySettings;
    }

    public PurchaseResponse purchase(long productId, PurchaseStrategy strategy) {
        long startedAt = System.nanoTime();

        if (strategy == PurchaseStrategy.PESSIMISTIC) {
            transactionService.purchasePessimistic(productId);
            return new PurchaseResponse(strategy, 1, 0, elapsedMicros(startedAt));
        }

        int attempts = 0;
        int retries = 0;

        while (true) {
            attempts++;
            try {
                transactionService.purchaseOptimistic(productId);
                return new PurchaseResponse(strategy, attempts, retries, elapsedMicros(startedAt));
            } catch (OptimisticLockingFailureException conflict) {
                if (retries >= retrySettings.maxRetries()) {
                    throw new RetryExhaustedException(
                            strategy, attempts, retries, elapsedMicros(startedAt), conflict);
                }

                long delayMillis = retryDelayPolicy.delayMillis(strategy, retries);
                retries++;
                sleep(delayMillis);
            }
        }
    }

    private void sleep(long delayMillis) {
        if (delayMillis <= 0) return;
        try {
            Thread.sleep(delayMillis);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("retry sleep interrupted", interrupted);
        }
    }

    private long elapsedMicros(long startedAt) {
        return TimeUnit.NANOSECONDS.toMicros(System.nanoTime() - startedAt);
    }
}
