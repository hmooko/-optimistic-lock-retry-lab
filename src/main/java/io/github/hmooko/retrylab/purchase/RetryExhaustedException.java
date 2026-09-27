package io.github.hmooko.retrylab.purchase;

public class RetryExhaustedException extends RuntimeException {
    private final PurchaseStrategy strategy;
    private final int attempts;
    private final int retries;
    private final long elapsedMicros;

    public RetryExhaustedException(
            PurchaseStrategy strategy,
            int attempts,
            int retries,
            long elapsedMicros,
            Throwable cause
    ) {
        super("optimistic retry exhausted: strategy=" + strategy
                + ", attempts=" + attempts + ", retries=" + retries, cause);
        this.strategy = strategy;
        this.attempts = attempts;
        this.retries = retries;
        this.elapsedMicros = elapsedMicros;
    }

    public PurchaseStrategy getStrategy() { return strategy; }
    public int getAttempts() { return attempts; }
    public int getRetries() { return retries; }
    public long getElapsedMicros() { return elapsedMicros; }
}
