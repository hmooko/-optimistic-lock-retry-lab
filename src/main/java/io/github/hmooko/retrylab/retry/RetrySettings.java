package io.github.hmooko.retrylab.retry;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "benchmark.retry")
public record RetrySettings(
        int maxRetries,
        long fixedDelayMs,
        long exponentialBaseMs,
        long exponentialCapMs,
        double jitterRatio
) {
    public RetrySettings {
        if (maxRetries < 0) throw new IllegalArgumentException("maxRetries must be >= 0");
        if (fixedDelayMs < 0 || exponentialBaseMs < 0 || exponentialCapMs < 0) {
            throw new IllegalArgumentException("delay values must be >= 0");
        }
        if (exponentialCapMs < exponentialBaseMs) {
            throw new IllegalArgumentException("exponentialCapMs must be >= exponentialBaseMs");
        }
        if (jitterRatio < 0.0 || jitterRatio >= 1.0) {
            throw new IllegalArgumentException("jitterRatio must be in [0, 1)");
        }
    }
}
